import Foundation
import AuralisRuntime

/// Bridges the kernel's ``PerformanceSignalEmitting`` seam to the app's real ``PerformanceRecording``
/// store: every terminal governed tool call — executed, failed, or blocked — becomes a durable
/// ``PerformanceEvent`` so tool-call health surfaces alongside playbook/operator health in Mission
/// Control (P0.5-204 "performance signals").
public struct PerformancePipelineSink: PerformanceSignalEmitting {
    private let store: any PerformanceRecording

    public init(store: any PerformanceRecording) {
        self.store = store
    }

    public func record(_ signal: PerformanceSignal) async {
        await store.record(
            PerformanceEvent(
                // Group tool-call performance by tool ID — operators share their ID between the tool
                // registry and the playbook world, so their health unifies naturally.
                playbookID: signal.toolID,
                outcome: Self.outcome(for: signal.outcome),
                durationSeconds: signal.durationSeconds,
                runID: signal.runID,
                triggerSource: "tool",
                failureReason: signal.failureReason,
                blockCategory: Self.blockCategory(for: signal.blockSource)
            )
        )
    }

    /// Maps a governed terminal outcome onto the performance taxonomy. The pipeline only emits
    /// signals for the three terminal tool-call outcomes; the pre-terminal `needsRevision` /
    /// `needsApproval` dispositions are handled defensively for exhaustiveness.
    private static func outcome(for outcome: GovernedOutcomeKind) -> PlaybookRunOutcome {
        switch outcome {
        case .executed: return .success
        case .failed: return .failed
        case .blocked: return .blocked
        case .needsRevision: return .blocked
        case .needsApproval: return .needsApproval
        }
    }

    private static func blockCategory(for source: PerformanceBlockSource?) -> PerformanceBlockCategory? {
        switch source {
        case .policy: return .policy
        case .authority: return .authority
        case .infrastructure: return .infrastructure
        case .other: return .other
        case nil: return nil
        }
    }
}
