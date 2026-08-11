/// Performs the real work of an authorized plan step.
///
/// PlannerCore deliberately ships no concrete executor: what a capability *does* lives in
/// the feature layer (playlists, exports, wallet flows). The orchestrator only calls this
/// for steps an authorizer has cleared, so an executor can assume it is allowed to act.
@MainActor
public protocol StepExecuting {
    func execute(_ step: PlanStep) async throws -> StepExecutionOutcome
}

/// The result of executing a step, summarized for the run report and receipts.
public struct StepExecutionOutcome: Equatable, Sendable {
    public let summary: String

    public init(summary: String) {
        self.summary = summary
    }
}
