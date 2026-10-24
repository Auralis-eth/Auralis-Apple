import Foundation
import ReceiptsCore
import RuntimeCore
@testable import RuntimeKit
import SocialCore
import Testing

/// Minimal in-memory receipt store so a host can be constructed for coordination wiring tests.
private actor CoordinationReceiptStore: ReceiptStore {
    private var records: [ReceiptRecord] = []
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        let record = ReceiptRecord(
            id: UUID(), sequenceID: records.count + 1, createdAt: receipt.createdAt,
            actor: receipt.actor, actorDetail: receipt.actorDetail, authorityDetail: receipt.authorityDetail, mode: receipt.mode, trigger: receipt.trigger,
            scope: receipt.scope, summary: receipt.summary, provenance: receipt.provenance,
            isSuccess: receipt.isSuccess, correlationID: receipt.correlationID, details: receipt.details
        )
        records.insert(record, at: 0)
        return record
    }
    func latest(limit: Int) async throws -> [ReceiptRecord] { Array(records.prefix(limit)) }
    func receipts(forCorrelationID correlationID: String, limit: Int) async throws -> [ReceiptRecord] {
        Array(records.filter { $0.correlationID == correlationID }.prefix(limit))
    }
    func exportAll() async throws -> Data { Data() }
    func resetAll() async throws { records.removeAll() }
}

@MainActor
@Suite("Human coordination wiring (P1-SOCIAL-101/102)")
struct SocialCoordinationTests {
    private func makeHost() -> RuntimeHost {
        RuntimeHost(receiptStore: CoordinationReceiptStore())
    }

    @Test("a due ritual with no executable playbooks is skipped without advancing its schedule")
    func emptyRitualDoesNotRecordFalseSuccess() async {
        let ritual = RitualDefinition(
            id: "ritual.test", kind: .weeklyReflection, name: "Test", summary: "",
            trigger: .schedule(intervalSeconds: 100), playbookIDs: [], isEnabled: false
        )
        let store = RitualStore(seed: [ritual])
        await store.setEnabled(id: ritual.id, true)
        let host = RuntimeHost(
            receiptStore: CoordinationReceiptStore(),
            coordination: RuntimeCoordinationStores(ritualStore: store)
        )

        let firedFirst = await host.runDueRituals(now: Date())
        #expect(firedFirst.isEmpty)
        #expect(await store.lastRun(id: ritual.id) == nil)
    }

    @Test("a scheduled ritual records its claimed occurrence instead of wall-clock completion time")
    func scheduledRitualRecordsOccurrenceTime() async {
        let ritual = RitualDefinition(
            id: "ritual.scheduled-test",
            kind: .morningReview,
            name: "Scheduled Test",
            summary: "",
            trigger: .schedule(intervalSeconds: 100),
            playbookIDs: ["research.brief"],
            isEnabled: true
        )
        let store = RitualStore(seed: [ritual])
        let host = RuntimeHost(
            receiptStore: CoordinationReceiptStore(),
            coordination: RuntimeCoordinationStores(ritualStore: store)
        )
        let occurrence = Date(timeIntervalSince1970: 1_000)

        let report = await host.runRitualReport(
            id: ritual.id,
            trigger: .schedule,
            scheduledOccurrence: occurrence
        )

        #expect(report.status == .completed)
        #expect(await store.lastRun(id: ritual.id) == occurrence)
    }

    @Test("Collaborative approval reaches its threshold and resolves approved")
    func collaborativeApprovalResolves() async {
        let host = makeHost()
        let session = await host.sharedSessionStore.create(
            SharedSession(correlationID: "c", title: "Group", createdBy: .human)
        )
        let requestID = UUID()
        _ = await host.openCollaborativeApproval(
            sessionID: session.id,
            approvalRequest: ApprovalRequest(
                id: requestID,
                proposal: ActionProposal(actor: .system, intent: "Ship", capability: .runPlugin, impact: .externalImpact),
                prompt: "Ship it?"
            ),
            prompt: "Ship it?",
            requiredApprovals: 1
        )
        let (updated, resolution) = await host.recordCollaborativeVote(
            sessionID: session.id, approvalID: updatedApprovalID(host: host, sessionID: session.id),
            actor: .human, approved: true
        )
        #expect(resolution == .approved)
        #expect(updated?.approvals.first?.approvalCount == 1)
    }

    /// Resolves the id of the single collaborative approval on a session (helper for the vote test).
    private func updatedApprovalID(host: RuntimeHost, sessionID: UUID) async -> UUID {
        await host.sharedSessionStore.session(id: sessionID)?.approvals.first?.id ?? UUID()
    }

    @Test("Shared workflow runs through the routine path and files workflow, artifact, and receipt into the session")
    func sharedWorkflowRunsAndFilesContext() async throws {
        let receiptStore = CoordinationReceiptStore()
        let host = RuntimeHost(receiptStore: receiptStore)
        let session = await host.sharedSessionStore.create(
            SharedSession(correlationID: "shared-flow", title: "Shared Flow", createdBy: .human)
        )

        let record = try #require(await host.runSharedWorkflow(sessionID: session.id, playbookID: "research.brief"))
        let updated = try #require(await host.sharedSessionStore.session(id: session.id))
        let artifactID = try #require(record.artifactID)

        #expect(record.outcome == .success)
        #expect(updated.sharedPlaybookIDs == ["research.brief"])
        #expect(updated.sharedArtifactIDs == [artifactID])
        #expect(updated.sharedReceiptIDs.count == 1)
        let receipts = try await receiptStore.receipts(forCorrelationID: session.correlationID, limit: 10)
        #expect(receipts.first?.details.values["runID"] == .string(record.id.uuidString))
    }

    @Test("Shared agent context is filed locally and queued for encrypted relay")
    func sharedAgentContextIsFiledAndQueued() async throws {
        let host = makeHost()
        let session = await host.sharedSessionStore.create(
            SharedSession(correlationID: "shared-context", title: "Context", createdBy: .human)
        )
        let context = SharedAgentContext(
            title: "Morning context",
            summary: "A public summary.",
            provenance: "runtime.context-bundle"
        )

        let updated = try #require(await host.shareAgentContext(
            context,
            sessionID: session.id,
            authorParticipantID: ActorRef.human.participantKey
        ))
        let snapshot = await host.socialEventLogStore.currentSnapshot()

        #expect(updated.sharedAgentContexts == [context])
        #expect(snapshot.pendingOutboundEventIDs.count == 1)
        #expect(snapshot.envelopes.first?.event == .agentContextShared(context))
    }

    @Test("Collaborative ritual creates a shared session and files produced artifacts into it")
    func collaborativeRitualCreatesSessionWithArtifacts() async throws {
        let host = makeHost()

        let report = await host.runRitualReport(id: "ritual.collaborative-listening")
        let session = try #require(await host.sharedSessionStore.allSessions().first)
        let snapshot = await host.socialEventLogStore.currentSnapshot()
        // Via the snapshot, which carries the log's provenance: the ritual author is a `.local`
        // identity and is only trusted because this installation minted the envelopes itself.
        let projection = snapshot.projection(sessionID: session.id)
        let run = try #require(projection.ritualRunDetails[report.ritualID])

        #expect(report.records.contains { $0.outcome == .success && $0.artifactID != nil })
        #expect(report.status == .completed)
        #expect(session.title == "Collaborative Listening")
        #expect(session.sharedArtifactIDs.isEmpty == false)
        #expect(session.sharedReceiptIDs.isEmpty == false)
        #expect(projection.title == session.title)
        #expect(projection.correlationID == session.correlationID)
        #expect(run.status == .completed)
        #expect(run.artifactIDs == session.sharedArtifactIDs)
        #expect(Set(run.receiptIDs) == Set(session.sharedReceiptIDs))
        #expect(snapshot.pendingOutboundEventIDs.isEmpty)
        #expect(snapshot.envelopes.contains { envelope in
            envelope.event == .ritualRunChanged(
                ritualID: report.ritualID,
                status: .started,
                artifactIDs: [],
                receiptIDs: []
            )
        })
    }

    @Test("Replaying collaborative ritual events is deterministic and deduplicates repeated delivery")
    func collaborativeRitualReplayIsDeterministic() async throws {
        let host = makeHost()

        _ = await host.runRitualReport(id: "ritual.collaborative-listening")
        let session = try #require(await host.sharedSessionStore.allSessions().first)
        let snapshot = await host.socialEventLogStore.currentSnapshot()
        let duplicated = snapshot.envelopes + snapshot.envelopes.reversed()

        let first = snapshot.projection(sessionID: session.id)
        let replayed = SocialSessionProjection.reduce(
            Array(duplicated),
            sessionID: session.id,
            locallyMintedEventIDs: snapshot.locallyMintedEventIDs
        )

        #expect(replayed == first)
        #expect(replayed.sharedArtifactIDs.count == Set(replayed.sharedArtifactIDs).count)
        #expect(replayed.sharedReceiptIDs.count == Set(replayed.sharedReceiptIDs).count)
    }

    @Test("Social event log persistence restores envelopes, pending outbound, invites, and cursors")
    func socialEventLogPersistenceRoundTrips() async throws {
        let suiteName = "RuntimeKitTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let persistence = try socialPersistence(suiteName: suiteName)
        let store = SocialEventLogStore(persistence: persistence)
        let sessionID = UUID()
        let invite = SocialInvite(
            sessionID: sessionID,
            relayTopic: "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: Date(timeIntervalSince1970: 200),
            nonce: "nonce"
        )
        let envelope = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "alice",
            authorCAIP10Account: "eip155:1:0xalice",
            createdAt: Date(timeIntervalSince1970: 10),
            event: .participantJoined(
                SocialParticipantIdentity(
                    participantID: "alice",
                    caip10Account: "eip155:1:0xalice",
                    displayName: "Alice",
                    role: .collaborator,
                    verificationState: .verified,
                    joinedAt: Date(timeIntervalSince1970: 10),
                    proofID: "proof"
                )
            )
        )

        await store.saveInvite(invite)
        await store.enqueueOutbound(envelope)
        await store.setReplayCursor(SocialRelayCursor(topic: "topic-a", lastReceivedAt: envelope.createdAt, lastEventID: envelope.id))

        let restored = SocialEventLogStore(persistence: persistence)
        let snapshot = await restored.currentSnapshot()

        #expect(snapshot.invites == [invite])
        #expect(snapshot.envelopes == [envelope])
        #expect(snapshot.pendingOutboundEventIDs == [envelope.id])
        #expect(snapshot.replayCursors["topic-a"]?.lastEventID == envelope.id)
    }

    @Test("Corrupt social event-log data is quarantined and cannot be overwritten implicitly")
    func corruptSocialEventLogIsQuarantined() async throws {
        let suiteName = "RuntimeKitTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let key = "corrupt.social"
        let corruptData = Data("not-json".utf8)
        let persistence = try socialPersistence(suiteName: suiteName, key: key, seed: corruptData)

        _ = await persistence.load()
        await persistence.save(SocialEventLogSnapshot())

        let reader = try #require(UserDefaults(suiteName: suiteName))
        #expect(reader.data(forKey: key) == corruptData)
        #expect(reader.data(forKey: key + UserDefaultsSocialEventLogPersistence.quarantineSuffix) == corruptData)
        guard case .quarantined = await persistence.persistenceHealth() else {
            Issue.record("Expected corrupt social state to be observable as quarantined")
            return
        }
    }

    @Test("Corrupt shared-session data is quarantined and cannot be overwritten implicitly")
    func corruptSharedSessionsAreQuarantined() async throws {
        let suiteName = "RuntimeKitTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let key = "corrupt.sessions"
        let corruptData = Data([0xFF, 0x00, 0xFE])
        let persistence = try sharedSessionPersistence(suiteName: suiteName, key: key, seed: corruptData)

        _ = await persistence.load()
        await persistence.save([])

        let reader = try #require(UserDefaults(suiteName: suiteName))
        #expect(reader.data(forKey: key) == corruptData)
        #expect(reader.data(forKey: key + UserDefaultsSharedSessionPersistence.quarantineSuffix) == corruptData)
        guard case .quarantined = await persistence.persistenceHealth() else {
            Issue.record("Expected corrupt shared-session state to be observable as quarantined")
            return
        }
    }

    @Test("Corrupt ritual data requires explicit discard before replacement")
    func corruptRitualStateRequiresExplicitRecovery() async throws {
        let suiteName = "RuntimeKitTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let key = "corrupt.ritual"
        let corruptData = Data("[]".utf8)
        let persistence = try ritualPersistence(suiteName: suiteName, key: key, seed: corruptData)

        _ = await persistence.load()
        await persistence.save(RitualPersistedState(enabledIDs: ["ritual.test"]))
        let reader = try #require(UserDefaults(suiteName: suiteName))
        #expect(reader.data(forKey: key) == corruptData)

        await persistence.discardQuarantinedPayload()
        await persistence.save(RitualPersistedState(enabledIDs: ["ritual.test"]))

        #expect(reader.data(forKey: key) != corruptData)
        #expect(await persistence.persistenceHealth() == .healthy)
    }

    // MARK: - Quarantine recovery wiring

    /// Quarantine is detected on a backing's first `load()`, and the ritual/shared-session stores
    /// defer that until first access — so the host has to touch them or the banner appears only
    /// once a person opens the collaboration surface.
    @Test("a quarantined coordination backing is reported on the host at bootstrap")
    func quarantinedBackingIsReportedAtBootstrap() async throws {
        let suiteName = "RuntimeKitTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let key = "corrupt.ritual.host"
        let persistence = try ritualPersistence(suiteName: suiteName, key: key, seed: Data("[]".utf8))
        let host = RuntimeHost(
            receiptStore: CoordinationReceiptStore(),
            coordination: RuntimeCoordinationStores(
                ritualStore: RitualStore(persistence: persistence),
                quarantinablePersistence: [persistence]
            )
        )

        #expect(host.coordinationPersistenceError == nil)
        await host.bootstrap()

        let reported = try #require(host.coordinationPersistenceError)
        #expect(reported.contains("Rituals"))
    }

    /// The privacy reset (MC-Device-012) over a quarantined payload.
    ///
    /// `reset()` writes an empty snapshot, which a quarantined backing refuses like any other
    /// `save` — and the seams are non-throwing, so nothing reported it. The payload this method
    /// exists to erase therefore survived "delete all local data", alongside the `.quarantine`
    /// copy the quarantine itself wrote. Both keys must be gone afterwards.
    @Test("resetAllHistory discards a quarantined payload instead of silently failing to erase it")
    func resetAllHistoryErasesQuarantinedCoordinationData() async throws {
        let suiteName = "RuntimeKitTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let key = "corrupt.sessions.reset"
        let corruptData = Data([0xFF, 0x00, 0xFE])
        let persistence = try sharedSessionPersistence(suiteName: suiteName, key: key, seed: corruptData)
        let host = RuntimeHost(
            receiptStore: CoordinationReceiptStore(),
            coordination: RuntimeCoordinationStores(
                sharedSessionStore: SharedSessionStore(persistence: persistence),
                quarantinablePersistence: [persistence]
            )
        )
        await host.bootstrap()
        let reader = try #require(UserDefaults(suiteName: suiteName))
        // Precondition: quarantine has taken hold and left both copies on disk.
        #expect(reader.data(forKey: key) == corruptData)
        #expect(reader.data(forKey: key + UserDefaultsSharedSessionPersistence.quarantineSuffix) == corruptData)

        try await host.resetAllHistory()

        // The quarantined copy is gone outright, and the primary key no longer holds the corrupt
        // bytes: the discard removed both, after which `reset()`'s empty snapshot could finally be
        // written. So the end state is a *readable, empty* store rather than the unreadable payload
        // that used to survive the reset in duplicate.
        #expect(reader.data(forKey: key + UserDefaultsSharedSessionPersistence.quarantineSuffix) == nil)
        let remaining = try #require(reader.data(forKey: key))
        #expect(remaining != corruptData)
        #expect(try JSONDecoder().decode([SharedSession].self, from: remaining).isEmpty)
        #expect(host.coordinationPersistenceError == nil)
        #expect(await persistence.persistenceHealth() == .healthy)
        #expect(await host.sharedSessionStore.allSessions().isEmpty)
    }

    @Test("discarding quarantined coordination state clears the banner and restores writing")
    func discardingQuarantinedStateRestoresWriting() async throws {
        let suiteName = "RuntimeKitTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let key = "corrupt.ritual.discard"
        let persistence = try ritualPersistence(suiteName: suiteName, key: key, seed: Data("[]".utf8))
        let ritualStore = RitualStore(persistence: persistence)
        let host = RuntimeHost(
            receiptStore: CoordinationReceiptStore(),
            coordination: RuntimeCoordinationStores(
                ritualStore: ritualStore,
                quarantinablePersistence: [persistence]
            )
        )
        await host.bootstrap()
        #expect(host.coordinationPersistenceError != nil)

        await host.discardQuarantinedCoordinationState()

        #expect(host.coordinationPersistenceError == nil)
        // The proof that writing works again: a toggle now reaches disk, where before the discard
        // every save was refused and the enabled-state reset on each launch.
        let ritualID = try #require(await ritualStore.all().first).id
        await ritualStore.setEnabled(id: ritualID, true)
        let reader = try #require(UserDefaults(suiteName: suiteName))
        let written = try #require(reader.data(forKey: key))
        let restored = try JSONDecoder().decode(RitualPersistedState.self, from: written)
        #expect(restored.enabledIDs.contains(ritualID))
    }

    /// A host with no quarantinable backing must not report one. The default coordination stores are
    /// ephemeral, so there is nothing that *can* quarantine and the banner has to stay silent.
    @Test("a host with ephemeral coordination stores reports no quarantine")
    func ephemeralCoordinationStoresReportNoQuarantine() async {
        let host = makeHost()
        await host.bootstrap()
        #expect(host.coordinationPersistenceError == nil)
    }

nonisolated private func socialPersistence(
    suiteName: String,
    key: String = UserDefaultsSocialEventLogPersistence.defaultKey,
    seed: Data? = nil
) throws -> UserDefaultsSocialEventLogPersistence {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        if let seed { defaults.set(seed, forKey: key) }
        return UserDefaultsSocialEventLogPersistence(defaults: defaults, key: key)
    }

    /// The discard is the recovery action for a *quarantined* backing, and it must not take the
    /// healthy ones with it.
    ///
    /// The three backings quarantine independently — that is the stated reason
    /// ``RuntimeHost/coordinationPersistenceError`` names each one — but the recovery is a single
    /// button in Mission Control wired to ``RuntimeHost/discardQuarantinedCoordinationState()``,
    /// which loops every registered persistence and calls `discardQuarantinedPayload()`
    /// unconditionally. None of the three implementations guards on its own health, so each one
    /// removes its primary key whether or not it had anything quarantined.
    ///
    /// So discarding one unreadable ritual payload also erased the healthy shared sessions and the
    /// healthy social event log — including the pending outbound relay queue, i.e. work a person had
    /// asked to publish. The confirmation dialog promises the opposite ("deletes the saved … data
    /// that this version cannot read").
    @Test("discarding a quarantined backing leaves the healthy backings intact")
    func discardOnlyAffectsQuarantinedBackings() async throws {
        let suiteName = "RuntimeKitTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let ritualKey = "mixed.ritual"
        let sessionKey = "mixed.sessions"
        // Unreadable: `RitualPersistedState` is an object, so a JSON array cannot decode into it.
        let ritual = try seededRitualPersistence(
            suiteName: suiteName,
            key: ritualKey,
            seed: Data("[]".utf8)
        )
        // Healthy, and holding a session a person can still see.
        let liveSession = SharedSession(correlationID: "corr-keep-me", title: "Keep Me", createdBy: .human)
        let sessions = try seededSharedSessionPersistence(
            suiteName: suiteName,
            key: sessionKey,
            seed: try JSONEncoder().encode([liveSession])
        )
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let host = RuntimeHost(
            receiptStore: CoordinationReceiptStore(),
            coordination: RuntimeCoordinationStores(
                sharedSessionStore: SharedSessionStore(persistence: sessions),
                ritualStore: RitualStore(persistence: ritual),
                quarantinablePersistence: [sessions, ritual]
            )
        )
        await host.bootstrap()

        // Precondition: exactly one backing is quarantined, and the other is healthy and loaded.
        let reported = try #require(host.coordinationPersistenceError)
        #expect(reported.contains("Rituals"))
        #expect(reported.contains("Shared sessions") == false)
        #expect(await sessions.persistenceHealth() == .healthy)
        #expect(await host.sharedSessionStore.allSessions().isEmpty == false)

        await host.discardQuarantinedCoordinationState()

        // The unreadable ritual payload and its quarantine copy are gone — that is the point.
        #expect(defaults.data(forKey: ritualKey) == nil)
        #expect(defaults.data(forKey: ritualKey + UserDefaultsRitualStatePersistence.quarantineSuffix) == nil)
        // And the healthy shared-session payload is untouched. This is what regressed.
        let surviving = try #require(
            defaults.data(forKey: sessionKey),
            "discarding a quarantined ritual payload erased the healthy shared-session payload"
        )
        #expect(try JSONDecoder().decode([SharedSession].self, from: surviving).first?.title == "Keep Me")
    }

    /// Seeds one key without clearing the suite, so a test can stage several backings with
    /// different health over the same `UserDefaults`.
    ///
    /// Each of these returns a single actor holding its *own* `UserDefaults` handle for the shared
    /// suite. A helper returning both at once puts one non-`Sendable` handle into two isolation
    /// regions, which the compiler rejects; separate handles onto the same suite are equivalent
    /// here and are what the existing helpers below already do against a `reader`.
    nonisolated private func seededSharedSessionPersistence(
        suiteName: String,
        key: String,
        seed: Data
    ) throws -> UserDefaultsSharedSessionPersistence {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(seed, forKey: key)
        return UserDefaultsSharedSessionPersistence(defaults: defaults, key: key)
    }

    nonisolated private func seededRitualPersistence(
        suiteName: String,
        key: String,
        seed: Data
    ) throws -> UserDefaultsRitualStatePersistence {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(seed, forKey: key)
        return UserDefaultsRitualStatePersistence(defaults: defaults, key: key)
    }

    nonisolated private func sharedSessionPersistence(
        suiteName: String,
        key: String,
        seed: Data
    ) throws -> UserDefaultsSharedSessionPersistence {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(seed, forKey: key)
        return UserDefaultsSharedSessionPersistence(defaults: defaults, key: key)
    }

    nonisolated private func ritualPersistence(
        suiteName: String,
        key: String,
        seed: Data
    ) throws -> UserDefaultsRitualStatePersistence {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(seed, forKey: key)
        return UserDefaultsRitualStatePersistence(defaults: defaults, key: key)
    }
}
