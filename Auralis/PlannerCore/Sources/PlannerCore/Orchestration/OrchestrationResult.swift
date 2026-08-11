import Foundation

/// What happened to a single step during an orchestration run.
public struct StepReport: Identifiable, Equatable, Sendable {
    /// The outcome of attempting the step.
    public enum Status: Equatable, Sendable {
        /// The step ran unattended; carries the executor's summary.
        case ran(summary: String)
        /// The step is allowed but needs the user's confirmation, so the run paused here.
        case pausedForConfirmation
        /// The step is not permitted in the current context.
        case blocked
        /// A prior step halted the run, so this step was not attempted.
        case skipped
        /// The step was authorized but its executor threw.
        case failed(String)
    }

    public let step: PlanStep
    public let authorization: StepAuthorization
    public let status: Status

    public var id: UUID { step.id }

    public init(step: PlanStep, authorization: StepAuthorization, status: Status) {
        self.step = step
        self.authorization = authorization
        self.status = status
    }
}

/// The outcome of running a whole ``Plan`` through the orchestrator.
public struct OrchestrationResult: Equatable, Sendable {
    public let plan: Plan
    public let reports: [StepReport]

    public init(plan: Plan, reports: [StepReport]) {
        self.plan = plan
        self.reports = reports
    }

    /// Steps that ran unattended.
    public var ranSteps: [StepReport] {
        reports.filter { if case .ran = $0.status { return true } else { return false } }
    }

    /// The first step the run paused on for confirmation, if any — the thing to surface
    /// to the user as "do you want me to do this?".
    public var pendingConfirmation: PlanStep? {
        reports.first { $0.status == .pausedForConfirmation }?.step
    }

    /// True when every step ran to completion with nothing blocked, paused, or failed.
    public var isComplete: Bool {
        !reports.isEmpty && reports.allSatisfy {
            if case .ran = $0.status { return true } else { return false }
        }
    }
}
