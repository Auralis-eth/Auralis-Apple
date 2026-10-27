import Foundation
import AuralisRuntime
@testable import SocialCore
import Testing

@Suite("Shared sessions (P1-SOCIAL-101)")
struct SharedSessionTests {
    @Test("Creator is seeded as owner")
    func creatorIsOwner() {
        let session = SharedSession(correlationID: "c1", title: "Group sesh", createdBy: .human)
        #expect(session.participants.count == 1)
        #expect(session.participants.first?.role == .owner)
        #expect(session.isActive)
    }

    @Test("Sharing is idempotent and end is terminal")
    func sharingAndEnding() {
        var session = SharedSession(correlationID: "c1", title: "T", createdBy: .human)
        let receipt = UUID()
        session.share(receiptID: receipt)
        session.share(receiptID: receipt)
        #expect(session.sharedReceiptIDs == [receipt])

        session.end()
        let firstEnd = session.endedAt
        session.end()
        #expect(session.endedAt == firstEnd)
        #expect(!session.isActive)
    }

    @Test("Collaborative approval resolves on threshold and blocks on any rejection")
    func collaborativeApproval() {
        var session = SharedSession(correlationID: "c1", title: "T", createdBy: .human)
        let alice = ActorRef(kind: .human, identifier: "alice")
        let bob = ActorRef(kind: .human, identifier: "bob")
        let viewer = ActorRef(kind: .human, identifier: "vic")
        session.addParticipant(alice, role: .collaborator)
        session.addParticipant(bob, role: .collaborator)
        session.addParticipant(viewer, role: .viewer)

        let approval = CollaborativeApproval(approvalRequestID: UUID(), prompt: "Ship it?", requiredApprovals: 2)
        session.openApproval(approval)

        session.vote(ApprovalVote(actor: alice, approved: true), onApproval: approval.id)
        #expect(session.approvals[0].resolution == .pending)

        // Viewer votes are ignored.
        session.vote(ApprovalVote(actor: viewer, approved: true), onApproval: approval.id)
        #expect(session.approvals[0].approvalCount == 1)

        session.vote(ApprovalVote(actor: bob, approved: true), onApproval: approval.id)
        #expect(session.approvals[0].resolution == .approved)

        // A later rejection blocks.
        session.vote(ApprovalVote(actor: bob, approved: false), onApproval: approval.id)
        #expect(session.approvals[0].resolution == .rejected)
    }

    /// Participant matching uses `ActorRef.identityKey` (kind + identifier), not a local key that
    /// could fall back to `displayName` or drop `kind`. Two consequences matter here: a cosmetic
    /// display name must not decide who may vote, and two different kinds sharing an identifier must
    /// not collapse into one voter — which would silently defeat a quorum.
    @Test("Participant identity ignores display names and keeps kinds distinct")
    func participantIdentityUsesActorIdentity() {
        var session = SharedSession(correlationID: "c1", title: "T", createdBy: .human)
        let alice = ActorRef(kind: .human, identifier: "alice")
        let aliceRenamed = ActorRef(kind: .human, identifier: "alice", displayName: "Alice A.")
        // Same identifier, different kind — a distinct party.
        let plannerNamedAlice = ActorRef(kind: .workflow, identifier: "alice")

        session.addParticipant(alice, role: .collaborator)
        // Re-adding the same person under a display name must not create a second participant.
        session.addParticipant(aliceRenamed, role: .collaborator)
        #expect(session.participants.count == 2, "owner + alice only")

        // A different kind with the same identifier is a different participant.
        session.addParticipant(plannerNamedAlice, role: .collaborator)
        #expect(session.participants.count == 3)

        let approval = CollaborativeApproval(approvalRequestID: UUID(), prompt: "Ship it?", requiredApprovals: 2)
        session.openApproval(approval)

        // Alice's vote is hers whether or not the display name is attached — a second vote from the
        // renamed ref replaces her first rather than counting twice.
        session.vote(ApprovalVote(actor: alice, approved: true), onApproval: approval.id)
        session.vote(ApprovalVote(actor: aliceRenamed, approved: true), onApproval: approval.id)
        #expect(session.approvals[0].approvalCount == 1)
        #expect(session.approvals[0].resolution == .pending)

        // The workflow sharing her identifier is a separate voter and does reach the threshold.
        session.vote(ApprovalVote(actor: plannerNamedAlice, approved: true), onApproval: approval.id)
        #expect(session.approvals[0].approvalCount == 2)
        #expect(session.approvals[0].resolution == .approved)
    }

    /// `removeParticipant(id:requestedBy:)` is the local-model twin of the owner-only
    /// `participantRemoved` authority that ``SocialOwnerAuthorityTests`` pins on the wire side, and
    /// it had no coverage at all. Mission Control calls into this model directly, so the wire rules
    /// never see these mutations — the guard here is the only one.
    @Test("Removing a participant is owner-only and never self-removal")
    func removeParticipantAuthority() {
        let host = ActorRef(kind: .human, identifier: "host")
        let alice = ActorRef(kind: .human, identifier: "alice")
        let bob = ActorRef(kind: .human, identifier: "bob")
        var session = SharedSession(correlationID: "c1", title: "T", createdBy: host)
        session.addParticipant(alice, role: .collaborator)
        session.addParticipant(bob, role: .viewer)
        #expect(session.participants.count == 3)

        // A collaborator cannot eject a peer…
        session.removeParticipant(id: bob.participantKey, requestedBy: alice.participantKey)
        #expect(session.participants.contains { $0.id == bob.participantKey })

        // …nor can a viewer, nor can a non-member naming itself as the requester.
        session.removeParticipant(id: alice.participantKey, requestedBy: bob.participantKey)
        session.removeParticipant(id: alice.participantKey, requestedBy: "not-a-member")
        #expect(session.participants.contains { $0.id == alice.participantKey })

        // The owner cannot remove itself: that is the one removal that strands the session with no
        // owner, after which nothing can be removed or re-roled ever again.
        session.removeParticipant(id: host.participantKey, requestedBy: host.participantKey)
        #expect(session.participants.contains { $0.id == host.participantKey })

        // The owner can remove someone else.
        session.removeParticipant(id: bob.participantKey, requestedBy: host.participantKey)
        #expect(session.participants.map(\.id) == [host.participantKey, alice.participantKey])
    }

    /// `end()` is documented as terminal, but only the `endedAt` idempotence was pinned. Every
    /// mutator carries its own `guard isActive`, and an ended session that still accepts members,
    /// shares, approvals, votes, or removals is a session whose record of what happened keeps
    /// changing after it closed.
    @Test("An ended session accepts no further mutations")
    func endedSessionRefusesMutations() {
        let host = ActorRef(kind: .human, identifier: "host")
        let alice = ActorRef(kind: .human, identifier: "alice")
        var session = SharedSession(correlationID: "c1", title: "T", createdBy: host)
        session.addParticipant(alice, role: .collaborator)
        let approval = CollaborativeApproval(approvalRequestID: UUID(), prompt: "Ship it?", requiredApprovals: 1)
        session.openApproval(approval)

        session.end()

        session.addParticipant(ActorRef(kind: .human, identifier: "late"), role: .collaborator)
        session.share(receiptID: UUID())
        session.share(artifactID: UUID())
        session.share(playbookID: "playbook.late")
        session.share(agentContext: SharedAgentContext(title: "t", summary: "s", provenance: "p"))
        session.openApproval(CollaborativeApproval(approvalRequestID: UUID(), prompt: "Late?", requiredApprovals: 1))
        session.vote(ApprovalVote(actor: alice, approved: true), onApproval: approval.id)
        session.removeParticipant(id: alice.participantKey, requestedBy: host.participantKey)

        #expect(session.participants.count == 2, "an ended session admitted or ejected a participant")
        #expect(session.sharedReceiptIDs.isEmpty)
        #expect(session.sharedArtifactIDs.isEmpty)
        #expect(session.sharedPlaybookIDs.isEmpty)
        #expect(session.sharedAgentContexts.isEmpty)
        #expect(session.approvals.count == 1, "an ended session opened a new approval")
        #expect(session.approvals[0].votes.isEmpty, "an ended session recorded a vote")
    }

    /// Synthesized `Codable` assigns stored properties directly, so a decoded approval skipped both
    /// invariants `resolution` depends on — and `resolution` *is* the multi-party sign-off this type
    /// exists to provide.
    ///
    /// `requiredApprovals: 0` makes `approvalCount >= requiredApprovals` true with **zero votes
    /// cast**, so an approval resolves itself as `.approved` the moment it is loaded. And because
    /// `record(_:)`'s one-vote-per-actor rule lived only in the mutator, a payload repeating one
    /// actor's vote counted it twice toward the threshold, resolving a 2-of-2 on one person's
    /// say-so. `SharedSession` round-trips its whole approval graph through
    /// ``SharedSessionPersisting`` on every launch, so the decode path is the one that matters.
    ///
    /// Fails against the pre-fix code, which decoded `0` and reported `.approved`.
    @Test("a decoded collaborative approval cannot resolve itself")
    func decodedCollaborativeApprovalIsBounded() throws {
        let id = UUID()
        let requestID = UUID()
        let zeroThreshold = """
        {"id":"\(id.uuidString)","approvalRequestID":"\(requestID.uuidString)",\
        "prompt":"Ship it?","requiredApprovals":0,"votes":[]}
        """
        let decoded = try JSONDecoder().decode(
            CollaborativeApproval.self,
            from: Data(zeroThreshold.utf8)
        )
        #expect(decoded.requiredApprovals == 1)
        #expect(decoded.resolution == .pending, "a decoded approval approved itself with no votes")

        // One actor, two votes: the threshold must still need two *people*.
        let alice = ActorRef(kind: .human, identifier: "alice")
        let stuffed = CollaborativeApproval(
            id: id,
            approvalRequestID: requestID,
            prompt: "Ship it?",
            requiredApprovals: 2,
            votes: [
                ApprovalVote(actor: alice, approved: true, castAt: Date(timeIntervalSince1970: 1)),
                ApprovalVote(actor: alice, approved: true, castAt: Date(timeIntervalSince1970: 2))
            ]
        )
        let roundTripped = try JSONDecoder().decode(
            CollaborativeApproval.self,
            from: try JSONEncoder().encode(stuffed)
        )
        #expect(roundTripped.approvalCount == 1, "one actor's vote was counted twice")
        #expect(roundTripped.resolution == .pending)
        // Latest wins, matching `record(_:)`.
        #expect(roundTripped.votes.first?.castAt == Date(timeIntervalSince1970: 2))

        // A legitimate approval still round-trips unchanged.
        let bob = ActorRef(kind: .human, identifier: "bob")
        var genuine = CollaborativeApproval(
            approvalRequestID: UUID(),
            prompt: "Ship it?",
            requiredApprovals: 2
        )
        genuine.record(ApprovalVote(actor: alice, approved: true, castAt: Date(timeIntervalSince1970: 1)))
        genuine.record(ApprovalVote(actor: bob, approved: true, castAt: Date(timeIntervalSince1970: 2)))
        #expect(
            try JSONDecoder().decode(
                CollaborativeApproval.self,
                from: try JSONEncoder().encode(genuine)
            ) == genuine
        )
    }

    /// `addParticipant(_:role:at:)` refuses a key the session already holds, and every reader
    /// assumes that: `vote` and `removeParticipant` resolve a participant with `first(where:)`. A
    /// decoded payload holding one actor twice therefore let *array order* decide the role that
    /// governs whether that person may vote or eject a peer — a stored session listing the owner as
    /// `.viewer` first resolves as a viewer, and one listing a viewer as `.owner` first resolves as
    /// the owner.
    ///
    /// Fails against the pre-fix code, which decoded four participants from two.
    @Test("a decoded session cannot hold one actor twice")
    func decodedSessionDeduplicatesParticipants() throws {
        let host = ActorRef(kind: .human, identifier: "host")
        let alice = ActorRef(kind: .human, identifier: "alice")
        var session = SharedSession(correlationID: "c", title: "T", createdBy: host)
        session.addParticipant(alice, role: .collaborator)

        var payload = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(session))
                as? [String: Any]
        )
        // The same two records again, plus a demotion of the owner appended after them.
        let encoded = try #require(payload["participants"] as? [[String: Any]])
        var demotedOwner = try #require(encoded.first)
        demotedOwner["role"] = SharedRole.viewer.rawValue
        payload["participants"] = encoded + encoded + [demotedOwner]

        let decoded = try JSONDecoder().decode(
            SharedSession.self,
            from: try JSONSerialization.data(withJSONObject: payload)
        )

        #expect(decoded.participants.count == 2)
        #expect(decoded.participants.map(\.id) == [host.participantKey, alice.participantKey])
        // First wins, matching `addParticipant`, so the trailing demotion cannot strip the owner.
        #expect(decoded.participants.first?.role == .owner)
    }

    /// The collection beside `participants` with the same add-guard, which was left without the
    /// same de-duplication.
    ///
    /// ``SharedSession/openApproval(_:)`` refuses an id the session already holds, so every reader
    /// treats one id as one approval: `vote(_:onApproval:)` writes through `firstIndex(where:)`,
    /// Mission Control counts outstanding sign-offs with
    /// `approvals.filter { $0.resolution == .pending }`, and it renders them in a `ForEach` keyed on
    /// ``CollaborativeApproval/id``, which is undefined for a repeated id. A duplicated approval is
    /// therefore counted twice while only one copy ever receives a vote — and the copies may carry
    /// different thresholds, so the one a reader sees need not be the one the votes went to.
    ///
    /// Fails against the pre-fix code, which decoded three approvals from one.
    @Test("a decoded session cannot hold one approval twice")
    func decodedSessionDeduplicatesApprovals() throws {
        let host = ActorRef(kind: .human, identifier: "host")
        var session = SharedSession(correlationID: "c", title: "T", createdBy: host)
        session.openApproval(
            CollaborativeApproval(
                approvalRequestID: UUID(),
                prompt: "Ship it?",
                requiredApprovals: 2
            )
        )

        var payload = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(session))
                as? [String: Any]
        )
        let encoded = try #require(payload["approvals"] as? [[String: Any]])
        // The same approval again, plus a copy whose threshold a reader must never pick up.
        var loosened = try #require(encoded.first)
        loosened["requiredApprovals"] = 1
        payload["approvals"] = encoded + encoded + [loosened]

        var decoded = try JSONDecoder().decode(
            SharedSession.self,
            from: try JSONSerialization.data(withJSONObject: payload)
        )

        #expect(decoded.approvals.count == 1, "one approval was counted more than once")
        // First wins, matching `openApproval`, so the trailing copy cannot lower the threshold.
        #expect(decoded.approvals.first?.requiredApprovals == 2)
        // And the single vote the model records lands in the only copy there is.
        let approvalID = try #require(decoded.approvals.first?.id)
        decoded.vote(ApprovalVote(actor: host, approved: true), onApproval: approvalID)
        #expect(decoded.approvals.filter { $0.resolution == .pending }.count == 1)
    }

    @Test("Store tracks active vs ended sessions")
    func store() async {
        let store = SharedSessionStore()
        let session = await store.create(SharedSession(correlationID: "c", title: "T", createdBy: .human))
        #expect(await store.activeSessions().count == 1)
        await store.mutate(id: session.id) { $0.end() }
        #expect(await store.activeSessions().isEmpty)
        #expect(await store.allSessions().count == 1)
    }

    @Test("Store persists sessions across instances via injected persistence")
    func storePersistence() async {
        let persistence = InMemorySharedSessionPersistence()
        let first = SharedSessionStore(persistence: persistence)
        let session = await first.create(SharedSession(correlationID: "c", title: "Persisted", createdBy: .human))
        await first.mutate(id: session.id) { $0.share(receiptID: UUID()) }

        // A brand-new store hydrates from the same backing.
        let second = SharedSessionStore(persistence: persistence)
        let restored = await second.allSessions()
        #expect(restored.count == 1)
        #expect(restored.first?.title == "Persisted")
        #expect(restored.first?.sharedReceiptIDs.count == 1)
    }
}

@Suite("Ritual engine (P1-SOCIAL-102)")
struct RitualTests {
    @Test("Catalog seeds the built-in rituals")
    func catalog() {
        #expect(!RitualCatalog.all.isEmpty)
        #expect(RitualCatalog.all.contains { $0.kind == .morningReview })
    }

    @Test("Disabled rituals are never due")
    func disabledNotDue() {
        let ritual = RitualDefinition(
            id: "r", kind: .weeklyReflection, name: "R", summary: "",
            trigger: .schedule(intervalSeconds: 10), playbookIDs: [], isEnabled: false
        )
        #expect(!RitualEngine.isDue(ritual, lastRun: nil))
    }

    @Test("Enabled scheduled ritual is due when never run and after its interval")
    func scheduledDue() {
        let ritual = RitualDefinition(
            id: "r", kind: .weeklyReflection, name: "R", summary: "",
            trigger: .schedule(intervalSeconds: 100), playbookIDs: ["p"], isEnabled: true
        )
        let now = Date()
        #expect(RitualEngine.isDue(ritual, lastRun: nil, now: now))
        #expect(!RitualEngine.isDue(ritual, lastRun: now.addingTimeInterval(-50), now: now))
        #expect(RitualEngine.isDue(ritual, lastRun: now.addingTimeInterval(-150), now: now))
        #expect(RitualEngine.plannedPlaybookIDs(for: ritual, lastRun: nil, now: now) == ["p"])
    }

    @Test("Manual rituals are never automatically due")
    func manualNotDue() {
        let ritual = RitualDefinition(
            id: "r", kind: .seshPrep, name: "R", summary: "",
            trigger: .manual, playbookIDs: ["p"], isEnabled: true
        )
        #expect(!RitualEngine.isDue(ritual, lastRun: nil))
    }

    @Test("Store enable/disable round-trips")
    func storeEnable() async {
        let store = RitualStore()
        let id = RitualCatalog.all[0].id
        await store.setEnabled(id: id, true)
        #expect(await store.enabled().contains { $0.id == id })
        await store.setEnabled(id: id, false)
        #expect(await store.enabled().isEmpty)
    }

    @Test("Catalog has no empty-playbook rituals and includes collaborative listening")
    func catalogIsComplete() {
        #expect(RitualCatalog.all.allSatisfy { !$0.playbookIDs.isEmpty })
        #expect(RitualCatalog.all.contains { $0.kind == .collaborativeListening })
    }

    @Test("Enabled state and last-run persist across instances")
    func statePersistence() async {
        let persistence = InMemoryRitualStatePersistence()
        let id = RitualCatalog.all.first { $0.trigger != .manual }!.id
        let runAt = Date(timeIntervalSince1970: 1_000)

        let first = RitualStore(persistence: persistence)
        await first.setEnabled(id: id, true)
        await first.recordRun(id: id, at: runAt)

        let second = RitualStore(persistence: persistence)
        #expect(await second.enabled().contains { $0.id == id })
        #expect(await second.lastRun(id: id) == runAt)
    }

    @Test("Due-ritual filter runs enabled scheduled rituals whose interval elapsed")
    func dueFilter() {
        let ritual = RitualDefinition(
            id: "r", kind: .weeklyReflection, name: "R", summary: "",
            trigger: .schedule(intervalSeconds: 100), playbookIDs: ["p"], isEnabled: true
        )
        let now = Date()
        let due = RitualEngine.dueRituals(
            from: [ritual],
            lastRun: { _ in now.addingTimeInterval(-200) },
            now: now
        )
        #expect(due.map(\.id) == ["r"])
        let notDue = RitualEngine.dueRituals(from: [ritual], lastRun: { _ in now }, now: now)
        #expect(notDue.isEmpty)
    }

    @Test("Calendar schedules honor wall-clock occurrence and last successful run")
    func calendarScheduleDue() {
        let schedule = RitualCalendarSchedule(
            frequency: .daily,
            hour: 8,
            timeZoneIdentifier: "UTC"
        )
        let ritual = RitualDefinition(
            id: "morning", kind: .morningReview, name: "Morning", summary: "",
            trigger: .schedule(intervalSeconds: 86_400), calendarSchedule: schedule,
            playbookIDs: ["research.brief"], isEnabled: true
        )
        let before = Date(timeIntervalSince1970: 1_735_718_399) // 2024-12-31 07:59:59 UTC
        let after = Date(timeIntervalSince1970: 1_735_718_401) // 2024-12-31 08:00:01 UTC

        #expect(RitualEngine.isDue(ritual, lastRun: nil, now: after))
        #expect(!RitualEngine.isDue(ritual, lastRun: after, now: after))
        #expect(RitualEngine.mostRecentOccurrence(for: schedule, at: before) != nil)
    }

    @Test("Ritual store admits only one concurrent run claim")
    func runClaimIsExclusive() async {
        let store = RitualStore()
        let id = RitualCatalog.all[0].id

        #expect(await store.beginRun(id: id))
        #expect(await store.beginRun(id: id) == false)
        await store.finishRun(id: id)
        #expect(await store.beginRun(id: id))
        await store.finishRun(id: id)
    }

    @Test("Completed scheduled occurrences remain claimed after store recreation")
    func completedOccurrenceClaimPersists() async {
        let persistence = InMemoryRitualStatePersistence()
        let ritualID = RitualCatalog.all[0].id
        let occurrence = RitualOccurrenceID(
            ritualID: ritualID,
            scheduledAt: Date(timeIntervalSince1970: 1_735_718_400)
        )
        let first = RitualStore(persistence: persistence)

        #expect(await first.beginRun(id: ritualID, occurrenceID: occurrence))
        await first.finishRun(id: ritualID, occurrenceID: occurrence, completed: true)

        let restored = RitualStore(persistence: persistence)
        #expect(await restored.beginRun(id: ritualID, occurrenceID: occurrence) == false)
    }

    @Test("Completed occurrence retention keeps only the newest bounded history")
    func completedOccurrenceRetentionIsBounded() async {
        let persistence = InMemoryRitualStatePersistence()
        let ritualID = RitualCatalog.all[0].id
        let store = RitualStore(persistence: persistence, maxCompletedOccurrenceCount: 2)
        let occurrences = (1...3).map {
            RitualOccurrenceID(ritualID: ritualID, scheduledAt: Date(timeIntervalSince1970: TimeInterval($0)))
        }
        for occurrence in occurrences {
            #expect(await store.beginRun(id: ritualID, occurrenceID: occurrence))
            await store.finishRun(id: ritualID, occurrenceID: occurrence, completed: true)
        }

        let restored = RitualStore(persistence: persistence, maxCompletedOccurrenceCount: 2)
        #expect(await restored.beginRun(id: ritualID, occurrenceID: occurrences[0]))
        await restored.finishRun(id: ritualID)
        #expect(await restored.beginRun(id: ritualID, occurrenceID: occurrences[1]) == false)
        #expect(await restored.beginRun(id: ritualID, occurrenceID: occurrences[2]) == false)
    }

    /// Synthesized `Codable` assigns stored properties directly, so a decoded schedule skipped every
    /// clamp in `init`. Custom rituals are reloaded from persistence on each launch, so an
    /// out-of-range payload survived relaunch intact — and `hour: 99` is a `DateComponents` match
    /// that no date can satisfy, making `mostRecentOccurrence` return `nil` and `isDue` read that as
    /// "not due". The ritual silently never ran again, with nothing surfaced.
    ///
    /// Fails against the pre-fix code, where the decoded values came back as 99 / 61 / 0.
    @Test("a decoded calendar schedule is clamped to a satisfiable range")
    func decodedCalendarScheduleIsClamped() throws {
        let json = """
        {"frequency":"weekly","hour":99,"minute":61,"weekday":0,"timeZoneIdentifier":"UTC"}
        """
        let decoded = try JSONDecoder().decode(RitualCalendarSchedule.self, from: Data(json.utf8))
        #expect(decoded.hour == 23)
        #expect(decoded.minute == 59)
        #expect(decoded.weekday == 1)

        // The point of the clamp: the schedule now resolves to a real occurrence.
        let occurrence = RitualEngine.mostRecentOccurrence(
            for: decoded,
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(occurrence != nil, "a decoded schedule stayed unsatisfiable, so the ritual never runs")

        // Negative values clamp to the other end, and an unknown zone falls back rather than throwing.
        let lower = """
        {"frequency":"weekly","hour":-5,"minute":-1,"weekday":99,"timeZoneIdentifier":"Mars/Olympus"}
        """
        let decodedLower = try JSONDecoder().decode(RitualCalendarSchedule.self, from: Data(lower.utf8))
        #expect(decodedLower.hour == 0)
        #expect(decodedLower.minute == 0)
        #expect(decodedLower.weekday == 7)
        #expect(TimeZone(identifier: decodedLower.timeZoneIdentifier) != nil)
    }

    /// A round-trip of a legitimate schedule must be unchanged by the clamping decoder.
    @Test("a legitimate calendar schedule round-trips unchanged")
    func validCalendarScheduleRoundTrips() throws {
        let schedule = RitualCalendarSchedule(frequency: .weekly, hour: 17, minute: 30, weekday: 6, timeZoneIdentifier: "UTC")
        let decoded = try JSONDecoder().decode(
            RitualCalendarSchedule.self,
            from: try JSONEncoder().encode(schedule)
        )
        #expect(decoded == schedule)
    }
}

/// A trivial in-memory backing shared between two store instances, to prove hydration works.
private actor SharedSessionBox {
    var sessions: [SharedSession] = []
    func set(_ sessions: [SharedSession]) { self.sessions = sessions }
    func get() -> [SharedSession] { sessions }
}

private struct InMemorySharedSessionPersistence: SharedSessionPersisting {
    private let box = SharedSessionBox()
    func load() async -> [SharedSession] { await box.get() }
    func save(_ sessions: [SharedSession]) async { await box.set(sessions) }
}

private actor RitualStateBox {
    var state = RitualPersistedState()
    func set(_ state: RitualPersistedState) { self.state = state }
    func get() -> RitualPersistedState { state }
}

private struct InMemoryRitualStatePersistence: RitualStatePersisting {
    private let box = RitualStateBox()
    func load() async -> RitualPersistedState { await box.get() }
    func save(_ state: RitualPersistedState) async { await box.set(state) }
}

/// The authority table that replaced `requiresVerifiedAuthor` + `requiresOwnerAuthor`.
///
/// The real guarantee here is the compiler's, not this suite's: ``SocialEvent/authority`` is a
/// single `switch` with **no `default`**, so a new `SocialEvent` case cannot be added without
/// stating its authority. That is precisely what the old pair of booleans could not enforce —
/// `requiresOwnerAuthor` ended in `default: return false`, so a new case silently became
/// non-owner-gated, and since the two were consulted at separate points in an ordered guard chain,
/// a case answering `false` to both skipped every author check in the function.
///
/// What this suite adds is the *classification*: that the three groups still contain what they are
/// meant to contain, since a mistaken mapping compiles fine.
@Suite("Social event authority")
struct SocialEventAuthorityTests {
    private func identity(_ id: String) -> SocialParticipantIdentity {
        SocialParticipantIdentity(
            participantID: id,
            caip10Account: "eip155:1:0x\(id)",
            displayName: id,
            role: .collaborator,
            verificationState: .pending
        )
    }

    /// Owner-only. `approvalResolved` is the non-obvious member: it writes `explicitResolution`,
    /// which outranks the vote tally, so binding authority alone would let one verified collaborator
    /// declare a 3-of-3 approved with zero votes.
    @Test("session-ending, removal, and approval resolution are owner-only")
    func ownerOnlyEvents() {
        let ownerOnly: [SocialEvent] = [
            .sessionEnded(endedAt: Date(timeIntervalSince1970: 1)),
            .participantRemoved(participantID: "collab"),
            .approvalResolved(approvalID: UUID(), resolution: .approved)
        ]
        for event in ownerOnly {
            #expect(event.authority == .ownerAuthor, "\(event)")
            // Ownership is additive, never an alternative to the binding check.
            #expect(event.authority.requiresBindingAuthor, "\(event)")
        }
    }

    /// Everything that changes shared state other members rely on.
    ///
    /// **All thirteen, deliberately.** An earlier version of this test listed nine, and the four it
    /// omitted included the two with the most reach: `queueSnapshotPublished` is what
    /// `SocialQueueApplier` writes into the user's real AuraPlay playlist, and `agentContextShared`
    /// carries summarized agent context. The compiler's exhaustiveness only forces a *new* case to
    /// be classified — moving an *existing* row from `.bindingAuthor` to `.eventSpecific` compiles
    /// clean and would make wire-authored whole-queue replacement land unauthenticated, because
    /// that case has no event-specific rule and falls to `default: break`. Only an explicit list
    /// catches that.
    @Test("shared-state mutations require a binding author")
    func bindingEvents() {
        let binding: [SocialEvent] = [
            .receiptShared(UUID()),
            .artifactShared(UUID()),
            .workflowShared("w"),
            .playlistShared("p"),
            .agentContextShared(
                SharedAgentContext(title: "t", summary: "s", provenance: "p")
            ),
            .approvalOpened(SocialApprovalDraft(prompt: "?", requiredApprovals: 1)),
            .approvalVoteCast(approvalID: UUID(), vote: SocialApprovalVote(participantID: "a", approved: true)),
            .ritualRunChanged(ritualID: "r", status: .completed, artifactIDs: [], receiptIDs: []),
            .queueProposalCreated(
                SocialQueueProposal(mediaItemID: "m", title: "t", proposedByParticipantID: "a")
            ),
            .queueVoteCast(SocialQueueVote(proposalID: UUID(), participantID: "a", approved: true)),
            .queueMutationAccepted(
                .acceptProposal(proposalID: UUID(), item: SocialQueueItem(mediaItemID: "m", title: "t"))
            ),
            .queueMutationRejected(proposalID: UUID()),
            .queueSnapshotPublished(SocialQueueSnapshot(items: []))
        ]
        for event in binding {
            #expect(event.authority == .bindingAuthor, "\(event)")
        }
    }

    /// Policed by their own rules rather than by the author binding — membership writes go through
    /// the provenance, foreign-record, role-escalation and account-binding guards instead.
    ///
    /// **`.eventSpecific` is a claim about the `switch`, and this test does not verify it.** It
    /// says "policed elsewhere", and when an earlier version of this suite asserted the membership
    /// of this bucket, `sessionCreated` was in it with no arm in `rejectionReason`'s `switch` at
    /// all — so it fell to `default: break` and was accepted unauthenticated from the relay, and
    /// this test pinned that as required behaviour. The structural answer is that the `switch` no
    /// longer has a `default`; the behavioural one is `sessionCreatedIsRefusedOffTheWire` below,
    /// which is what makes the word "policed" mean anything here.
    @Test("membership and session creation are governed by their own rules")
    func eventSpecificEvents() {
        let eventSpecific: [SocialEvent] = [
            .sessionCreated(title: "t", correlationID: "c"),
            .participantJoined(identity("newcomer")),
            .participantUpdated(identity("newcomer")),
            // The forward-compatibility case: an event kind this build does not know. It applies
            // nothing, so it needs no author — but it must still be *stated*, which is the point.
            .unsupported(kind: "some.future.event")
        ]
        for event in eventSpecific {
            #expect(event.authority == .eventSpecific, "\(event)")
            #expect(event.authority.requiresBindingAuthor == false, "\(event)")
        }
    }

    /// The rule that makes `sessionCreated`'s `.eventSpecific` classification safe.
    ///
    /// Fails against the pre-fix code: with no `case .sessionCreated` arm the envelope fell through
    /// to `default: break` and `rejectionReason` returned `nil`.
    ///
    /// The backdated variant is the one that mattered. `apply` really is first-write-only
    /// (`title = title ?? …`), but "first" is `reduce`'s sort on the wire's own `createdAt`, so an
    /// attacker buys first place with `.distantPast` and the host's genuine title and
    /// `correlationID` — the key tying shared receipts, worklogs and artifacts together — become
    /// permanent no-ops.
    @Test("session creation is refused off the wire, including when backdated")
    func sessionCreatedIsRefusedOffTheWire() {
        let sessionID = UUID()
        let host = SocialParticipantIdentity(
            participantID: "host",
            caip10Account: "eip155:1:0xhost",
            displayName: "Host",
            role: .owner,
            verificationState: .local
        )
        let joined = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "host",
            createdAt: Date(timeIntervalSince1970: 1),
            event: .participantJoined(host)
        )
        let projection = SocialSessionProjection.reduce(
            [joined],
            sessionID: sessionID,
            locallyMintedEventIDs: [joined.id]
        )

        let forged = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "host",
            createdAt: .distantPast,
            event: .sessionCreated(title: "Attacker's title", correlationID: "attacker-chosen")
        )
        #expect(projection.rejectionReason(for: forged, isLocallyMinted: false) == .impersonatedAuthor)

        // The host's own creation still projects.
        let genuine = SocialEventEnvelope(
            sessionID: sessionID,
            authorParticipantID: "host",
            event: .sessionCreated(title: "Morning Review", correlationID: "corr-1")
        )
        #expect(projection.rejectionReason(for: genuine, isLocallyMinted: true) == nil)
    }

    /// `.unsupported` grants no state, so it needs no author — but it is still *stored*, and for a
    /// joined session nothing ever releases it. The bound is therefore on what is kept, not on who
    /// said it.
    @Test("unsupported payloads are bounded at the storage boundary")
    func unsupportedPayloadIsClamped() {
        let huge = String(repeating: "a", count: 40_000)
        let envelope = SocialEventEnvelope(
            sessionID: UUID(),
            authorParticipantID: huge,
            event: .unsupported(kind: huge)
        )
        let stored = envelope.clampedForStorage
        guard case let .unsupported(kind) = stored.event else {
            Issue.record("expected .unsupported, got \(stored.event)")
            return
        }
        #expect(kind.count == SocialParticipantIdentity.identifierLimit)
        #expect(stored.authorParticipantID.count == SocialParticipantIdentity.identifierLimit)
    }

    /// Synthesized `Codable` assigns stored properties directly, so every clamp written into an
    /// initializer is bypassed on exactly the path that can be hostile. This pins the decode route
    /// specifically, because that is the one the relay uses.
    @Test("a decoded identity is still bounded once stored")
    func decodedIdentityIsClampedAtStorage() throws {
        let huge = String(repeating: "n", count: 40_000)
        let json = """
        {"participantID":"\(huge)","caip10Account":"eip155:1:0xabc","displayName":"\(huge)",\
        "role":"collaborator","verificationState":"pending","joinedAt":0}
        """
        let decoded = try JSONDecoder().decode(SocialParticipantIdentity.self, from: Data(json.utf8))
        // Decode bypasses `init`, which is the whole problem.
        #expect(decoded.displayName.count == 40_000)

        let clamped = decoded.clampedForStorage
        #expect(clamped.displayName.count == SocialParticipantIdentity.displayNameLimit)
        #expect(clamped.participantID.count == SocialParticipantIdentity.identifierLimit)
    }

    /// The payload that is reconciled straight into the user's real AuraPlay playlist.
    ///
    /// `SocialQueueSnapshot` has no item cap of its own, so a single envelope could carry hundreds
    /// of fabricated entries. An earlier version of `clampedForStorage` listed this case under a
    /// comment claiming it held "UUIDs, enums, counts and already-bounded value types" — which was
    /// false for seven of the cases grouped there.
    @Test("a published queue snapshot is bounded in items and in each item's text")
    func queueSnapshotIsClamped() {
        let huge = String(repeating: "t", count: 40_000)
        let items = (0..<(SocialEvent.queueItemLimit + 250)).map { _ in
            SocialQueueItem(mediaItemID: huge, title: huge)
        }
        let clamped = SocialEvent.queueSnapshotPublished(SocialQueueSnapshot(items: items))
            .clampedForStorage
        guard case let .queueSnapshotPublished(snapshot) = clamped else {
            Issue.record("expected .queueSnapshotPublished, got \(clamped)")
            return
        }
        #expect(snapshot.items.count == SocialEvent.queueItemLimit)
        #expect(snapshot.items[0].title.count == SocialParticipantIdentity.displayNameLimit)
        #expect(snapshot.items[0].mediaItemID.count == SocialParticipantIdentity.identifierLimit)
    }

    /// An approval prompt is free text shown to a human before they sign off on something.
    @Test("an approval prompt is bounded")
    func approvalPromptIsClamped() {
        let clamped = SocialEvent.approvalOpened(
            SocialApprovalDraft(prompt: String(repeating: "p", count: 40_000), requiredApprovals: 2)
        ).clampedForStorage
        guard case let .approvalOpened(draft) = clamped else {
            Issue.record("expected .approvalOpened, got \(clamped)")
            return
        }
        #expect(draft.prompt.count == SocialEvent.promptLimit)
        #expect(draft.requiredApprovals == 2)
    }

    /// Payload-side participant ids share `authorParticipantID`'s limit on purpose.
    ///
    /// `rejectionReason` compares the two for equality (`vote.participantID !=
    /// envelope.authorParticipantID` → `.mismatchedAuthor`). Clamping one side and not the other
    /// would store an over-long author id as two different strings, leaving the event permanently
    /// inert after diagnostics had already reported it accepted.
    @Test("payload participant ids are clamped to the same limit as the envelope's author")
    func payloadParticipantIDsMatchTheAuthorLimit() {
        let huge = String(repeating: "v", count: 40_000)
        let stored = SocialEventEnvelope(
            sessionID: UUID(),
            authorParticipantID: huge,
            event: .queueVoteCast(
                SocialQueueVote(proposalID: UUID(), participantID: huge, approved: true)
            )
        ).clampedForStorage
        guard case let .queueVoteCast(vote) = stored.event else {
            Issue.record("expected .queueVoteCast, got \(stored.event)")
            return
        }
        #expect(vote.participantID == stored.authorParticipantID)
    }

    /// An invite is wire data that travels by camera rather than by relay, and it was the one type
    /// here with no field bounds at all.
    ///
    /// The load-bearing half is `inviterParticipantID`. `saveInvite` copies it into
    /// `ownerAnchorsBySessionID`, and `ownerBootstrapIsOpen` compares that anchor for equality
    /// against `SocialEventEnvelope.authorParticipantID` — which *is* clamped to `identifierLimit`
    /// at the storage boundary. Bounding one side of an equality comparison and not the other is the
    /// exact defect `payloadParticipantIDsMatchTheAuthorLimit` above pins for the payload ids: the
    /// two sides store as different strings, so the anchor matches no author that can ever exist and
    /// owner bootstrap never opens for that session.
    @Test("an invite's identifier fields share the envelope author's limit")
    func inviteIdentifiersMatchTheAuthorLimit() {
        let huge = String(repeating: "i", count: 40_000)
        let invite = SocialInvite(
            sessionID: UUID(),
            relayTopic: huge,
            encryptedSessionKey: huge,
            inviterParticipantID: huge,
            expiresAt: Date(timeIntervalSince1970: 10_000),
            nonce: huge
        )
        #expect(invite.inviterParticipantID.count == SocialParticipantIdentity.identifierLimit)
        #expect(invite.relayTopic.count == SocialParticipantIdentity.identifierLimit)
        #expect(invite.nonce.count == SocialParticipantIdentity.identifierLimit)

        // The anchor and the clamped author id must now be the same string.
        let envelope = SocialEventEnvelope(
            sessionID: invite.sessionID,
            authorParticipantID: huge,
            event: .unsupported(kind: "x")
        ).clampedForStorage
        #expect(envelope.authorParticipantID == invite.inviterParticipantID)

        // Opaque ciphertext is deliberately left alone: its length belongs to the key-wrapping
        // scheme, and truncating it would destroy the session key rather than bound anything.
        #expect(invite.encryptedSessionKey.count == 40_000)
    }

    /// Decode is the route an invite actually arrives by, and synthesized `Codable` bypasses `init`.
    @Test("a decoded invite is clamped, and a legitimate one round-trips unchanged")
    func decodedInviteIsClamped() throws {
        let huge = String(repeating: "i", count: 40_000)
        let sessionID = UUID()
        let json = """
        {"version":1,"sessionID":"\(sessionID.uuidString)","relayTopic":"\(huge)",\
        "encryptedSessionKey":"key","inviterParticipantID":"\(huge)",\
        "expiresAt":0,"nonce":"\(huge)"}
        """
        let decoded = try JSONDecoder().decode(SocialInvite.self, from: Data(json.utf8))
        #expect(decoded.inviterParticipantID.count == SocialParticipantIdentity.identifierLimit)
        #expect(decoded.relayTopic.count == SocialParticipantIdentity.identifierLimit)
        #expect(decoded.nonce.count == SocialParticipantIdentity.identifierLimit)

        let genuine = SocialInvite(
            sessionID: sessionID,
            relayTopic: String(repeating: "a", count: 64),
            encryptedSessionKey: "c2Vzc2lvbi1rZXk=",
            inviterParticipantID: "eip155:1:0x1234567890abcdef1234567890abcdef12345678",
            expiresAt: Date(timeIntervalSince1970: 10_000),
            nonce: String(repeating: "b", count: 32)
        )
        let roundTripped = try JSONDecoder().decode(
            SocialInvite.self,
            from: try JSONEncoder().encode(genuine)
        )
        #expect(roundTripped == genuine)
    }

    /// Clamping one type and not the one it is compared against is the bug shape that produced the
    /// `inviterParticipantID` finding — and bounding ``SocialInvite`` created a second instance of
    /// it, because ``SocialJoinChallenge`` is compared against the invite field by field.
    ///
    /// Unbounded on the challenge side, an over-long topic or nonce makes a legitimate challenge
    /// fail against its own invite and surface as the actively misleading `.wrongRelayTopic` or
    /// `.replayedNonce`. It reaches past the comparison too: both fields are interpolated into
    /// `signingMessage`, so the two sides disagreeing means the wallet signs a message that does not
    /// describe the invite being joined.
    @Test("a join challenge and its invite clamp identically")
    func joinChallengeAndInviteClampIdentically() {
        let huge = String(repeating: "h", count: 40_000)
        let invite = SocialInvite(
            sessionID: UUID(),
            relayTopic: huge,
            encryptedSessionKey: "key",
            inviterParticipantID: huge,
            expiresAt: Date(timeIntervalSince1970: 10_000),
            nonce: huge
        )
        let challenge = SocialJoinChallenge(invite: invite, caip10Account: huge)

        // The pair the validator compares must agree, or a genuine join is refused.
        #expect(challenge.relayTopic == invite.relayTopic)
        #expect(challenge.nonce == invite.nonce)
        #expect(challenge.caip10Account.count == SocialParticipantIdentity.identifierLimit)

        // Including via the memberwise initializer, which is the one a caller reaches for directly.
        let direct = SocialJoinChallenge(
            sessionID: invite.sessionID,
            relayTopic: huge,
            caip10Account: huge,
            nonce: huge,
            expiresAt: invite.expiresAt
        )
        #expect(direct == challenge)

        // And the validator actually accepts the pair rather than reporting a misleading mismatch.
        var validator = SocialJoinChallengeValidator()
        let proof = try? validator.acceptVerifiedSignature(
            invite: invite,
            challenge: challenge,
            verificationMethod: "0xsig",
            signatureVerified: true,
            now: Date(timeIntervalSince1970: 1_000)
        )
        #expect(proof != nil, "a clamped invite and its own challenge failed to match")
    }

    /// Decode is the path that matters once ``SocialParticipantProof`` starts travelling.
    @Test("a decoded join challenge is clamped, and a legitimate one round-trips unchanged")
    func decodedJoinChallengeIsClamped() throws {
        let huge = String(repeating: "h", count: 40_000)
        let sessionID = UUID()
        let json = """
        {"sessionID":"\(sessionID.uuidString)","relayTopic":"\(huge)",\
        "caip10Account":"\(huge)","nonce":"\(huge)","expiresAt":0}
        """
        let decoded = try JSONDecoder().decode(SocialJoinChallenge.self, from: Data(json.utf8))
        #expect(decoded.relayTopic.count == SocialParticipantIdentity.identifierLimit)
        #expect(decoded.caip10Account.count == SocialParticipantIdentity.identifierLimit)
        #expect(decoded.nonce.count == SocialParticipantIdentity.identifierLimit)

        let genuine = SocialJoinChallenge(
            sessionID: sessionID,
            relayTopic: String(repeating: "a", count: 64),
            caip10Account: "eip155:1:0x1234567890abcdef1234567890abcdef12345678",
            nonce: String(repeating: "b", count: 32),
            expiresAt: Date(timeIntervalSince1970: 10_000)
        )
        let roundTripped = try JSONDecoder().decode(
            SocialJoinChallenge.self,
            from: try JSONEncoder().encode(genuine)
        )
        #expect(roundTripped == genuine)
        // The signed message is identical across the round trip, which is the property that matters.
        #expect(roundTripped.signingMessage == genuine.signingMessage)
    }
}
