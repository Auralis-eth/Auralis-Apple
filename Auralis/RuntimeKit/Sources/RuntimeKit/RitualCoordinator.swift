import AuralisPrimaryModels
import AuralisFoundation
import Foundation
import OSLog
import AuralisRuntime
import PolicyCore
import ReceiptsCore
import SocialCore

/// Rituals, shared sessions, and the Social v1 event log (P1-SOCIAL-101/102).
///
/// This is the decomposition `RuntimeHost+Coordination.swift` named and deferred: that file's own
/// header said "This is a file split, not a decomposition… Extracting a `RitualCoordinator`
/// collaborator is the real fix and a larger, riskier change." The behaviour here is unchanged from
/// that extension; what changed is that it is no longer part of ``RuntimeHost``.
///
/// Two things make the move worth its size. The host shed roughly six hundred lines and ten public
/// methods from a type that had accumulated autopilot, routines, capability leases, receipts,
/// improvement recommendations, the privacy reset, *and* all of this. And the ritual surface became
/// testable on its own: everything it needs arrives through the initializer — ``RoutineRunning`` and
/// ``RuntimeDegradationReporting`` rather than a `RuntimeHost` handle — so a test can drive a ritual
/// against a recording double instead of composing a whole runtime.
///
/// The host's public ritual API is unchanged and delegates here, so nothing outside `RuntimeKit`
/// moved. `RuntimeHost.RitualRunStatus`, `RitualRunReport`, and `RitualAvailability` stay nested on
/// the host because Mission Control and the app notifier name them that way.
@MainActor
final class RitualCoordinator {
    private let rituals: RitualStore
    private let sharedSessions: SharedSessionStore
    private let socialEventLog: SocialEventLogStore
    private let playbooks: any PlaybookStore
    private let receipts: any ReceiptStore
    private let events: RuntimeEventBus
    private let notifier: any RitualRunNotifying
    private let cryptoMode: @MainActor () -> CryptoMode
    /// The host, as the two capabilities this type actually uses it for.
    ///
    /// `weak` because the host owns this coordinator, so a strong reference either way would be a
    /// cycle that outlives the app's runtime. Neither can be `nil` while a call is in flight — the
    /// only way to reach a method here is through the host that holds it — so the guards below are
    /// for the compiler's benefit rather than a reachable degraded path.
    private weak var routines: (any RoutineRunning)?
    private weak var degradation: (any RuntimeDegradationReporting)?

    init(
        rituals: RitualStore,
        sharedSessions: SharedSessionStore,
        socialEventLog: SocialEventLogStore,
        playbooks: any PlaybookStore,
        receipts: any ReceiptStore,
        events: RuntimeEventBus,
        notifier: any RitualRunNotifying,
        cryptoMode: @escaping @MainActor () -> CryptoMode,
        routines: any RoutineRunning,
        degradation: any RuntimeDegradationReporting
    ) {
        self.rituals = rituals
        self.sharedSessions = sharedSessions
        self.socialEventLog = socialEventLog
        self.playbooks = playbooks
        self.receipts = receipts
        self.events = events
        self.notifier = notifier
        self.cryptoMode = cryptoMode
        self.routines = routines
        self.degradation = degradation
    }

    // MARK: - Reading a run's evidence

    /// How many receipts to read back when filing a session's evidence, for `runCount` playbook runs.
    ///
    /// ``ReceiptStore/receipts(forCorrelationID:limit:)`` has no pagination, so this single fetch is
    /// the only chance to see the run's receipts and anything past the limit is silently dropped from
    /// the session and from the social events derived from it. The previous bounds were far too tight
    /// to be safe: `runSharedWorkflow` asked for 10 and `runRitualReport` for `max(20, runs * 4)`,
    /// while a single run can write a routine receipt, a governed pipeline receipt per tool call, and
    /// — since capability grants became auditable — a receipt per lease issued. A three-playbook
    /// ritual could therefore exceed 20 and file a partial set as if it were complete.
    ///
    /// The allowance is deliberately far above any realistic run rather than tuned tight. It bounds a
    /// single indexed read, so over-asking costs almost nothing, whereas under-asking silently
    /// corrupts the evidence a shared session presents.
    static func sessionReceiptFetchLimit(forRunCount runCount: Int) -> Int {
        max(128, runCount * 32)
    }

    /// Reads back the receipts a run wrote, so they can be filed as a shared session's evidence.
    ///
    /// A failed read is logged rather than folded into "the run produced no receipts". Both call
    /// sites used `try?` and defaulted to an empty array, which is the same defect the fetch-limit
    /// note above exists to prevent — a session presenting a partial (here, empty) set of receipts as
    /// though it were complete — except with no bound at all on how much was lost. The distinction
    /// matters to a reader: a genuinely receipt-free run and an unreadable ledger look identical in
    /// the session, and only one of them means the evidence still exists somewhere.
    ///
    /// Logging is the reporting channel available. This is a *read* failure, so the observable
    /// ``RuntimeHost/receiptPersistenceError`` banner would misdescribe it — nothing failed to save —
    /// and the ledger is intact for a later retry. Same posture as
    /// ``RuntimeHost/routineEventSignals(now:)`` takes for an unreadable artifact store.
    private func sessionReceipts(forCorrelationID correlationID: String, runCount: Int) async -> [ReceiptRecord] {
        do {
            return try await receipts.receipts(
                forCorrelationID: correlationID,
                limit: Self.sessionReceiptFetchLimit(forRunCount: runCount)
            )
        } catch {
            runtimeHostLogger.error(
                """
                Failed to read the receipts for correlation \(correlationID, privacy: .public); \
                the shared session will record no receipt evidence for this run even though the \
                receipts themselves may exist: \(error.localizedDescription, privacy: .public)
                """
            )
            return []
        }
    }

    // MARK: - Shared sessions (P1-SOCIAL-101)

    /// Runs a playbook as shared-session work, then files the produced workflow, artifact, and routine
    /// receipt into the session. The routine itself still uses the same governed scheduling path.
    @discardableResult
    func runSharedWorkflow(
        sessionID: UUID,
        playbookID: String,
        trigger: TriggerSource,
        actor: ActorRef?
    ) async -> ExecutionRecord? {
        guard let routines,
              let session = await sharedSessions.session(id: sessionID),
              session.isActive else { return nil }
        await sharedSessions.mutate(id: sessionID) { $0.share(playbookID: playbookID) }
        let record = await routines.runRoutine(
            id: playbookID,
            trigger: trigger,
            actor: actor,
            correlationID: session.correlationID
        )
        await sharedSessions.mutate(id: sessionID) { session in
            if let artifactID = record.artifactID {
                session.share(artifactID: artifactID)
            }
        }
        let receipts = await sessionReceipts(forCorrelationID: session.correlationID, runCount: 1)
        // One mutation for the whole set: `mutate` persists every stored session on each call, so a
        // per-receipt loop rewrote the entire session list once per receipt. `runRitualReport` files
        // its receipts the same way.
        await sharedSessions.mutate(id: sessionID) { session in
            for receipt in receipts {
                session.share(receiptID: receipt.id)
            }
        }
        await events.publish(
            WorkflowEventEnvelope(
                event: .executionUpdate("Shared workflow \(playbookID) ran in session \(sessionID.uuidString)"),
                correlationID: session.correlationID
            )
        )
        return record
    }

    /// Shares an intentionally bounded context summary with an active session and records the matching
    /// relay event. Raw prompts, credentials, and arbitrary memory are not accepted by this API;
    /// callers must reference durable artifacts for fuller context.
    ///
    /// Sharing is an explicit publish request, so the event is queued for the relay regardless of
    /// whether the author holds a wallet proof — the alternative would be a Share button that does
    /// nothing in an ordinary local session.
    ///
    /// - Parameter authorVerificationState: Whether the author's control of `authorCAIP10Account` has
    ///   actually been proven. A parameter rather than something inferred here because nothing on the
    ///   session can answer it: ``SharedParticipant`` carries an ``ActorRef`` and a role, not a proof.
    ///   Defaults to `.local`, the honest answer for an author nobody has verified.
    ///
    ///   This is what the account is *for*. The method used to build its envelope by hand and pass
    ///   `authorCAIP10Account` straight through, while every other host-originated social event went
    ///   through ``enqueueSocialEvents(sessionID:author:events:delivery:)``, which attaches the
    ///   account only for a verified author. So an unproven wallet address could ride out to the
    ///   relay on the one path carrying user-authored prose. Both paths now share that rule.
    @discardableResult
    func shareAgentContext(
        _ context: SharedAgentContext,
        sessionID: UUID,
        authorParticipantID: String,
        authorCAIP10Account: String?,
        authorVerificationState: SocialParticipantVerificationState
    ) async -> SharedSession? {
        guard context.isExpired(at: .now) == false,
              let current = await sharedSessions.session(id: sessionID),
              let participant = current.participants.first(where: { $0.id == authorParticipantID }),
              current.isActive,
              participant.role.canVote else {
            return nil
        }
        let updated = await sharedSessions.mutate(id: sessionID) { session in
            session.share(agentContext: context)
            for artifactID in context.artifactIDs {
                session.share(artifactID: artifactID)
            }
        }
        await enqueueSocialEvents(
            sessionID: sessionID,
            author: SocialParticipantIdentity(
                participantID: authorParticipantID,
                // `enqueueSocialEvents` only reads this when the author is verified, so the local
                // placeholder is never what gets published — it mirrors the identity the ritual path
                // builds for the same unverified case.
                caip10Account: authorCAIP10Account ?? "auralis:local:\(authorParticipantID)",
                displayName: participant.actor.displayName ?? participant.actor.kind.displayTitle,
                role: participant.role,
                verificationState: authorVerificationState
            ),
            events: [.agentContextShared(context)],
            delivery: .publish
        )
        await events.publish(
            WorkflowEventEnvelope(
                event: .executionUpdate("Shared agent context “\(context.title)”"),
                correlationID: current.correlationID
            )
        )
        return updated
    }

    /// P1-SOCIAL-101 — Opens a collaborative approval on a shared session: a runtime `ApprovalRequest`
    /// that needs sign-off from more than one participant before it may proceed. Returns the updated
    /// session, or `nil` when the session is unknown.
    @discardableResult
    func openCollaborativeApproval(
        sessionID: UUID,
        approvalRequest: ApprovalRequest,
        prompt: String,
        requiredApprovals: Int
    ) async -> SharedSession? {
        guard let current = await sharedSessions.session(id: sessionID), current.isActive else { return nil }
        let approval = CollaborativeApproval(
            approvalRequestID: approvalRequest.id,
            approvalRequest: approvalRequest,
            prompt: prompt,
            requiredApprovals: requiredApprovals
        )
        let session = await sharedSessions.mutate(id: sessionID) { $0.openApproval(approval) }
        await events.publish(
            WorkflowEventEnvelope(event: .executionUpdate("Collaborative approval opened: \(prompt)"))
        )
        return session
    }

    /// Records a participant's vote on a collaborative approval and returns the updated session plus
    /// the approval's resolution, so the caller can drive the single-actor runtime approval flow the
    /// moment collaborative sign-off resolves (approved on threshold, rejected on any objection).
    func recordCollaborativeVote(
        sessionID: UUID,
        approvalID: UUID,
        actor: ActorRef,
        approved: Bool
    ) async -> (session: SharedSession?, resolution: ApprovalResolution?) {
        let current = await sharedSessions.session(id: sessionID)
        guard current?.isActive == true else {
            return (current, nil)
        }
        let session = await sharedSessions.mutate(id: sessionID) {
            $0.vote(ApprovalVote(actor: actor, approved: approved), onApproval: approvalID)
        }
        let resolution = session?.approvals.first { $0.id == approvalID }?.resolution
        return (session, resolution)
    }

    // MARK: - Rituals (P1-SOCIAL-102)
    //
    // Each of a ritual's playbooks goes through the same governed routine path as any other run, so
    // authority envelopes, receipts, and performance all apply unchanged. A collaborative ritual
    // (`RitualKind.isCollaborative`) opens a shared session and files every artifact the run
    // produces into it, so the ritual literally drives a shared session — the P1-SOCIAL-101 ↔ 102
    // seam. Runs record the ritual's last-run time so scheduled triggers stay due-correct.

    func ritualAvailability(id: String) async -> RuntimeHost.RitualAvailability? {
        guard let ritual = await rituals.ritual(id: id) else { return nil }
        var installed: [String] = []
        var unavailable: [String] = []
        for playbookID in ritual.playbookIDs {
            do {
                if try await playbooks.playbook(id: playbookID)?.installState == .installed {
                    installed.append(playbookID)
                } else {
                    unavailable.append(playbookID)
                }
            } catch {
                degradation?.reportPlaybookPersistenceError(error)
                unavailable.append(playbookID)
            }
        }
        return RuntimeHost.RitualAvailability(
            ritualID: id,
            installedPlaybookIDs: installed,
            unavailablePlaybookIDs: unavailable
        )
    }

    /// Runs a ritual and returns an explicit aggregate result. A ritual with no executable playbooks
    /// is skipped and does not advance its schedule. The store claim makes manual/background overlap
    /// idempotent within the running process.
    @discardableResult
    func runRitualReport(
        id: String,
        trigger: TriggerSource,
        actor: ActorRef?,
        scheduledOccurrence: Date?
    ) async -> RuntimeHost.RitualRunReport {
        guard let ritual = await rituals.ritual(id: id) else {
            return RuntimeHost.RitualRunReport(ritualID: id, status: .skipped, records: [], unavailablePlaybookIDs: [])
        }
        let occurrenceID = scheduledOccurrence.map {
            RitualOccurrenceID(ritualID: id, scheduledAt: $0)
        }
        guard await rituals.beginRun(id: id, occurrenceID: occurrenceID) else {
            return RuntimeHost.RitualRunReport(ritualID: id, status: .alreadyRunning, records: [], unavailablePlaybookIDs: [])
        }
        let availability = await ritualAvailability(id: id)
        let availablePlaybookIDs = availability?.installedPlaybookIDs ?? []
        let unavailablePlaybookIDs = availability?.unavailablePlaybookIDs ?? ritual.playbookIDs
        guard availablePlaybookIDs.isEmpty == false else {
            await events.publish(
                WorkflowEventEnvelope(event: .executionUpdate("Ritual “\(ritual.name)” skipped: no installed playbooks"))
            )
            await notifier.notify(ritual: ritual, status: .skipped)
            await rituals.finishRun(id: id, occurrenceID: occurrenceID, completed: false)
            return RuntimeHost.RitualRunReport(
                ritualID: id,
                status: .skipped,
                records: [],
                unavailablePlaybookIDs: unavailablePlaybookIDs
            )
        }

        let ritualActor = actor ?? ritual.createdBy
        var sharedSession: SharedSession?
        if ritual.kind.isCollaborative {
            let session = await sharedSessions.create(
                SharedSession(correlationID: UUID().uuidString, title: ritual.name, createdBy: ritual.createdBy)
            )
            sharedSession = session
            let participant = Self.localParticipant(for: ritualActor)
            await enqueueSocialEvents(
                sessionID: session.id,
                author: participant,
                events: [
                    .sessionCreated(title: session.title, correlationID: session.correlationID),
                    .participantJoined(participant),
                    .ritualRunChanged(
                        ritualID: ritual.id,
                        status: .started,
                        artifactIDs: [],
                        receiptIDs: []
                    )
                ],
                // A ritual's run log is a local record. It is published only once the author can be
                // proved, and `ritualActor` is `.local` by construction here.
                delivery: participant.verificationState == .verified ? .publish : .localOnly
            )
        }
        var records: [ExecutionRecord] = []
        for playbookID in availablePlaybookIDs {
            guard Task.isCancelled == false, let routines else { break }
            let record = await routines.runRoutine(
                id: playbookID,
                trigger: trigger,
                actor: ritualActor,
                correlationID: sharedSession?.correlationID
            )
            records.append(record)
            if let sharedSession, let artifactID = record.artifactID {
                await sharedSessions.mutate(id: sharedSession.id) { $0.share(artifactID: artifactID) }
            }
        }
        let successfulCount = records.filter { $0.outcome == .success || $0.outcome == .noOp }.count
        let wasCancelled = Task.isCancelled
        let status: RuntimeHost.RitualRunStatus
        if wasCancelled {
            status = .failed
        } else if records.isEmpty {
            // The loop above ran nothing despite `availablePlaybookIDs` being non-empty, which means
            // it broke on its first iteration because ``routines`` was gone. Unreachable while the
            // host that owns this coordinator is alive (see that property), but it must not fall
            // through to the comparison below: `successfulCount == records.count` holds trivially at
            // 0 == 0, so a ritual whose every playbook was installed would report `.completed`,
            // notify as completed, and call `recordRun` — advancing the schedule past an occurrence
            // where nothing happened.
            status = .failed
        } else if successfulCount == records.count, unavailablePlaybookIDs.isEmpty {
            status = .completed
        } else if successfulCount > 0 {
            status = .partiallyCompleted
        } else {
            status = .failed
        }
        if status == .completed || status == .partiallyCompleted {
            await rituals.recordRun(id: id, at: scheduledOccurrence ?? .now)
        }
        if let sharedSession {
            let artifactIDs = records.compactMap(\.artifactID)
            let runReceipts = await sessionReceipts(
                forCorrelationID: sharedSession.correlationID,
                runCount: records.count
            )
            let receiptIDs = runReceipts.map(\.id)
            await sharedSessions.mutate(id: sharedSession.id) { session in
                for receiptID in receiptIDs {
                    session.share(receiptID: receiptID)
                }
            }
            let participant = Self.localParticipant(for: ritualActor)
            // One write for the whole run's worth of events, in the same order they were previously
            // appended individually.
            await enqueueSocialEvents(
                sessionID: sharedSession.id,
                author: participant,
                events: artifactIDs.map { .artifactShared($0) }
                    + receiptIDs.map { .receiptShared($0) }
                    + [
                        .ritualRunChanged(
                            ritualID: ritual.id,
                            status: Self.socialRitualStatus(for: status),
                            artifactIDs: artifactIDs,
                            receiptIDs: receiptIDs
                        )
                    ],
                delivery: participant.verificationState == .verified ? .publish : .localOnly
            )
        }
        await events.publish(
            WorkflowEventEnvelope(event: .executionUpdate("Ritual “\(ritual.name)” \(status.rawValue): \(records.count) playbook(s)"))
        )
        await notifier.notify(ritual: ritual, status: status)
        await rituals.finishRun(
            id: id,
            occurrenceID: occurrenceID,
            completed: status == .completed || status == .partiallyCompleted
        )
        return RuntimeHost.RitualRunReport(
            ritualID: id,
            status: status,
            records: records,
            unavailablePlaybookIDs: unavailablePlaybookIDs
        )
    }

    /// Runs every enabled ritual whose trigger is due (P1-SOCIAL-102 auto-scheduling). Mirrors
    /// ``RuntimeHost/runDueRoutines(now:staleSignal:approvalPendingSignal:scanCorrelationID:)`` for
    /// rituals: the background scheduler calls this so scheduled rituals (morning review, weekly
    /// reflection) actually fire on their own, not only on a manual tap. Last-run state comes from the
    /// ritual store; kill-switch-aware because each underlying playbook run short-circuits inside the
    /// paused scheduling engine.
    @discardableResult
    func runDueRituals(
        now: Date,
        staleSignal: Bool,
        approvalPendingSignal: Bool
    ) async -> [String] {
        let enabled = await rituals.enabled()
        var lastRuns: [String: Date] = [:]
        for ritual in enabled {
            lastRuns[ritual.id] = await rituals.lastRun(id: ritual.id)
        }
        let due = RitualEngine.dueRituals(
            from: enabled,
            lastRun: { lastRuns[$0.id] },
            now: now,
            staleSignal: staleSignal,
            approvalPendingSignal: approvalPendingSignal
        )
        var firedIDs: [String] = []
        for ritual in due {
            guard Task.isCancelled == false else { break }
            // Automated fire: the ritual itself is the acting routine (P0.5-602).
            let report = await runRitualReport(
                id: ritual.id,
                trigger: PlaybookTriggerMapping.triggerSource(for: ritual.trigger),
                actor: ActorRef(kind: .scheduledRoutine, identifier: ritual.id, displayName: ritual.name),
                scheduledOccurrence: ritual.calendarSchedule.flatMap {
                    RitualEngine.mostRecentOccurrence(for: $0, at: now)
                }
            )
            if report.didExecute {
                firedIDs.append(ritual.id)
            }
        }
        return firedIDs
    }

    // MARK: - Social event log

    /// Whether a batch of social events is only recorded on this installation or also queued for the
    /// relay to publish.
    ///
    /// An explicit parameter because the two kinds of social event genuinely differ and used to
    /// diverge by accident. A ritual's events are a *record* of what ran on this device, so they
    /// wait until the author can be proved before being broadcast under their name. An agent-context
    /// share is a *request to publish* — withholding it until the author happens to hold a wallet
    /// proof would mean the feature silently did nothing in an ordinary local session. Naming the
    /// choice at each call site keeps that a decision rather than a side effect of which helper
    /// someone reached for.
    enum SocialEventDelivery {
        /// Record here only; stay out of the relay outbox.
        case localOnly
        /// Record here and queue for the relay to publish.
        case publish
    }

    /// Files a run of social events under one author in a single durable write.
    ///
    /// Batched rather than looped because `SocialEventLogStore` re-encodes and rewrites its entire
    /// snapshot per mutation. A collaborative ritual emits one event per produced artifact and one
    /// per receipt, so enqueuing them individually rewrote the whole (monotonically growing) log
    /// twenty-plus times per scheduled run.
    ///
    /// The CAIP-10 account is attached only for a `.verified` author, and that rule holds for *both*
    /// deliveries. It is the part that is not negotiable: an unproven wallet address must not ride
    /// along on an envelope, least of all one bound for a relay. `shareAgentContext` used to build
    /// its envelope by hand and pass the caller's account through as given, which skipped this.
    func enqueueSocialEvents(
        sessionID: UUID,
        author: SocialParticipantIdentity,
        events socialEvents: [SocialEvent],
        delivery: SocialEventDelivery
    ) async {
        guard !socialEvents.isEmpty else { return }
        let envelopes = socialEvents.map { event in
            SocialEventEnvelope(
                sessionID: sessionID,
                authorParticipantID: author.participantID,
                authorCAIP10Account: author.verificationState == .verified ? author.caip10Account : nil,
                event: event
            )
        }
        switch delivery {
        case .publish:
            await socialEventLog.enqueueOutbound(envelopes)
        case .localOnly:
            await socialEventLog.appendLocal(envelopes)
        }
    }

    /// The unverified, local-only identity a ritual acts under.
    ///
    /// One helper rather than the two identical literals `runRitualReport` used to build at its start
    /// and its end, which could drift apart while describing the same author in the same run.
    private static func localParticipant(for actor: ActorRef) -> SocialParticipantIdentity {
        SocialParticipantIdentity(
            participantID: actor.participantKey,
            caip10Account: "auralis:local:\(actor.participantKey)",
            displayName: actor.displayName ?? actor.kind.displayTitle,
            role: .owner,
            verificationState: .local
        )
    }

    private static func socialRitualStatus(for status: RuntimeHost.RitualRunStatus) -> SocialRitualRunStatus {
        switch status {
        case .completed:
            return .completed
        case .partiallyCompleted:
            return .partiallyCompleted
        case .failed:
            return .failed
        case .skipped, .alreadyRunning:
            return .skipped
        }
    }

    /// Drops coordination history that has aged past ``SocialRetentionPolicy`` — complete, long-
    /// terminated session graphs and stale invites. Active sessions and anything still pending in
    /// the relay outbox are never truncated, so deterministic replay is unaffected.
    ///
    /// Called from ``RuntimeHost/bootstrap()`` so it runs once per launch **regardless of whether
    /// the relay is enabled**. That independence is the point. The only other caller of
    /// `SocialEventLogStore.prune` is `SocialRelayCoordinator.subscribeToSavedInvites()`, which
    /// opens with `try ensureEnabled()` — so with the Social v1 relay flag off, nothing pruned at
    /// all. Meanwhile ``runRitualReport(id:trigger:actor:scheduledOccurrence:)`` appends one
    /// envelope per produced artifact and per receipt on every collaborative ritual run, into a
    /// `UserDefaults`-backed snapshot that is re-encoded and rewritten whole on each mutation. The
    /// log only grew, and the cost of every subsequent write grew with it.
    @discardableResult
    func pruneCoordinationHistory(
        now: Date,
        policy: SocialRetentionPolicy
    ) async -> SocialPruneResult {
        await socialEventLog.prune(now: now, policy: policy)
    }

    /// Persists a privacy-safe Social v1 diagnostic. Callers pass stable classifications only; relay
    /// topics, ciphertext, wallet proof, and shared content are deliberately excluded.
    func recordSocialDiagnostic(
        kind: String,
        reason: String,
        sessionID: UUID?,
        eventID: UUID?,
        isSuccess: Bool
    ) async {
        var values: [String: ReceiptJSONValue] = [
            "kind": .string(kind),
            "reason": .string(reason)
        ]
        if let sessionID { values["sessionID"] = .string(sessionID.uuidString) }
        if let eventID { values["eventID"] = .string(eventID.uuidString) }
        // Named, not `.system`: these receipts are written by the relay diagnostic path specifically,
        // and `.system` would file them under the same identity as every other unattributed internal
        // write — leaving the trace unable to say which workflow produced them.
        let actor = ActorRef(kind: .workflow, identifier: "social.diagnostic")
        let draft = ReceiptDraft(
            actorDetail: actor.receiptActorDetail,
            authorityDetail: .policyDefault(
                reason: "Standing policy permits recording privacy-safe Social coordination diagnostics."
            ),
            // The host's actual posture, not a hardcoded `.observe`. Every other receipt this type
            // writes stamps `cryptoMode.receiptMode`, and the mode column is only worth reading if
            // it reports the mode the app was really in when the record was written.
            mode: cryptoMode().receiptMode,
            trigger: "social.diagnostic",
            scope: "social",
            summary: "Social coordination diagnostic: \(kind)",
            provenance: "local",
            isSuccess: isSuccess,
            correlationID: sessionID?.uuidString,
            details: ReceiptPayload(values: values)
        )
        let receipt: ReceiptRecord
        do {
            receipt = try await receipts.append(draft)
        } catch {
            // Routed through the same degraded-evidence path as every other receipt write. This was
            // a `try?` that discarded the error — the one thing the runtime is not allowed to do
            // with a receipt (see ``RuntimeHost/noteReceiptPersistenceFailure(correlationID:goal:actor:)``),
            // and especially not here: the record being lost is itself the evidence that a relay
            // operation failed, so a silent drop hid both the relay fault and its own absence.
            await degradation?.noteReceiptPersistenceFailure(
                correlationID: sessionID?.uuidString ?? "social.diagnostic",
                goal: "Social coordination diagnostic",
                actor: actor
            )
            return
        }
        await events.publish(
            WorkflowEventEnvelope(event: .receiptCreated(id: receipt.id), correlationID: receipt.correlationID)
        )
    }
}
