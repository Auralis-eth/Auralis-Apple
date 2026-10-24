import Foundation
import RuntimeCore
import SchedulingCore
import SocialCore

// The host's public face for rituals, shared sessions, and the Social v1 event log
// (P1-SOCIAL-101/102).
//
// The logic lives in ``RitualCoordinator``; this file is the delegation layer plus the three result
// types that have to stay nested on ``RuntimeHost`` because Mission Control
// (`MissionControlHomeModel`) and the app's notifier (`LocalRitualRunNotifier`) already name them
// `RuntimeHost.RitualRunReport`, `RuntimeHost.RitualAvailability`, and
// `RuntimeHost.RitualRunStatus`. Keeping them here is what made the extraction a no-op for every
// caller outside `RuntimeKit`.
//
// This file previously held the whole surface, and said so: "This is a file split, not a
// decomposition… Extracting a `RitualCoordinator` collaborator is the real fix and a larger,
// riskier change." That extraction has now happened.
@MainActor
extension RuntimeHost {
    /// How a ritual run ended, aggregated across its playbooks.
    public enum RitualRunStatus: String, Equatable, Sendable {
        case completed
        case partiallyCompleted
        case failed
        case skipped
        case alreadyRunning
    }

    public struct RitualRunReport: Equatable, Sendable {
        public let ritualID: String
        public let status: RitualRunStatus
        public let records: [ExecutionRecord]
        public let unavailablePlaybookIDs: [String]

        public var didExecute: Bool { records.isEmpty == false }
    }

    public struct RitualAvailability: Equatable, Sendable {
        public let ritualID: String
        public let installedPlaybookIDs: [String]
        public let unavailablePlaybookIDs: [String]

        public var isAvailable: Bool {
            installedPlaybookIDs.isEmpty == false && unavailablePlaybookIDs.isEmpty
        }
        public var canRun: Bool { installedPlaybookIDs.isEmpty == false }
    }

    // MARK: - Shared sessions (P1-SOCIAL-101)

    /// Runs a playbook as shared-session work, then files the produced workflow, artifact, and routine
    /// receipt into the session. The routine itself still uses the same governed scheduling path.
    @discardableResult
    public func runSharedWorkflow(
        sessionID: UUID,
        playbookID: String,
        trigger: TriggerSource = .manual,
        actor: ActorRef? = nil
    ) async -> ExecutionRecord? {
        await ritualCoordinator.runSharedWorkflow(
            sessionID: sessionID,
            playbookID: playbookID,
            trigger: trigger,
            actor: actor
        )
    }

    /// Shares an intentionally bounded context summary with an active session and records the matching
    /// relay event. See ``RitualCoordinator/shareAgentContext(_:sessionID:authorParticipantID:authorCAIP10Account:authorVerificationState:)``
    /// for why the verification state is a parameter rather than something inferred.
    @discardableResult
    public func shareAgentContext(
        _ context: SharedAgentContext,
        sessionID: UUID,
        authorParticipantID: String,
        authorCAIP10Account: String? = nil,
        authorVerificationState: SocialParticipantVerificationState = .local
    ) async -> SharedSession? {
        await ritualCoordinator.shareAgentContext(
            context,
            sessionID: sessionID,
            authorParticipantID: authorParticipantID,
            authorCAIP10Account: authorCAIP10Account,
            authorVerificationState: authorVerificationState
        )
    }

    /// P1-SOCIAL-101 — Opens a collaborative approval on a shared session: a runtime `ApprovalRequest`
    /// that needs sign-off from more than one participant before it may proceed.
    @discardableResult
    public func openCollaborativeApproval(
        sessionID: UUID,
        approvalRequest: ApprovalRequest,
        prompt: String,
        requiredApprovals: Int
    ) async -> SharedSession? {
        await ritualCoordinator.openCollaborativeApproval(
            sessionID: sessionID,
            approvalRequest: approvalRequest,
            prompt: prompt,
            requiredApprovals: requiredApprovals
        )
    }

    /// Records a participant's vote on a collaborative approval and returns the updated session plus
    /// the approval's resolution, so the caller can drive the single-actor runtime approval flow the
    /// moment collaborative sign-off resolves.
    public func recordCollaborativeVote(
        sessionID: UUID,
        approvalID: UUID,
        actor: ActorRef,
        approved: Bool
    ) async -> (session: SharedSession?, resolution: ApprovalResolution?) {
        await ritualCoordinator.recordCollaborativeVote(
            sessionID: sessionID,
            approvalID: approvalID,
            actor: actor,
            approved: approved
        )
    }

    // MARK: - Rituals (P1-SOCIAL-102)

    public func ritualAvailability(id: String) async -> RitualAvailability? {
        await ritualCoordinator.ritualAvailability(id: id)
    }

    /// Runs a ritual and returns an explicit aggregate result. A ritual with no executable playbooks
    /// is skipped and does not advance its schedule.
    @discardableResult
    public func runRitualReport(
        id: String,
        trigger: TriggerSource = .manual,
        actor: ActorRef? = nil,
        scheduledOccurrence: Date? = nil
    ) async -> RitualRunReport {
        // Bootstrapped here and not left to the per-playbook ``runRoutine`` calls underneath: a
        // ritual publishes events, opens a collaborative shared session, and notifies before its
        // first routine runs — and the `.skipped` path (no installed playbooks) reaches none of them
        // at all. See ``RuntimeHost/runRoutine(id:trigger:actor:correlationID:)``.
        await bootstrap()
        return await ritualCoordinator.runRitualReport(
            id: id,
            trigger: trigger,
            actor: actor,
            scheduledOccurrence: scheduledOccurrence
        )
    }

    /// Compatibility convenience for callers that only need the individual execution records.
    @discardableResult
    public func runRitual(
        id: String,
        trigger: TriggerSource = .manual,
        actor: ActorRef? = nil
    ) async -> [ExecutionRecord] {
        await runRitualReport(id: id, trigger: trigger, actor: actor).records
    }

    /// Runs every enabled ritual whose trigger is due (P1-SOCIAL-102 auto-scheduling).
    @discardableResult
    public func runDueRituals(
        now: Date = .now,
        staleSignal: Bool = false,
        approvalPendingSignal: Bool = false
    ) async -> [String] {
        // The second half of the background refresh's work; see ``runDueRoutines``.
        await bootstrap()
        return await ritualCoordinator.runDueRituals(
            now: now,
            staleSignal: staleSignal,
            approvalPendingSignal: approvalPendingSignal
        )
    }

    // MARK: - Social event log

    /// Drops coordination history that has aged past ``SocialRetentionPolicy``. Called from
    /// ``bootstrap()`` so it runs once per launch regardless of whether the relay is enabled; see
    /// ``RitualCoordinator/pruneCoordinationHistory(now:policy:)`` for why that independence matters.
    @discardableResult
    public func pruneCoordinationHistory(
        now: Date = .now,
        policy: SocialRetentionPolicy = SocialRetentionPolicy()
    ) async -> SocialPruneResult {
        await ritualCoordinator.pruneCoordinationHistory(now: now, policy: policy)
    }

    /// Persists a privacy-safe Social v1 diagnostic. Callers pass stable classifications only; relay
    /// topics, ciphertext, wallet proof, and shared content are deliberately excluded.
    public func recordSocialDiagnostic(
        kind: String,
        reason: String,
        sessionID: UUID?,
        eventID: UUID? = nil,
        isSuccess: Bool = false
    ) async {
        await ritualCoordinator.recordSocialDiagnostic(
            kind: kind,
            reason: reason,
            sessionID: sessionID,
            eventID: eventID,
            isSuccess: isSuccess
        )
    }
}

// MARK: - Collaborator conformances

/// Lets ``RitualCoordinator`` start a routine without holding a `RuntimeHost`. The witness is the
/// host's existing governed path, so a ritual's playbook runs are indistinguishable from any other
/// routine run — which is the property that made a protocol seam safe here.
extension RuntimeHost: RoutineRunning { }

/// Routes the coordinator's unpropagatable persistence failures onto the host's observable banners,
/// so there is one degraded-evidence signal in the runtime rather than two.
extension RuntimeHost: RuntimeDegradationReporting { }
