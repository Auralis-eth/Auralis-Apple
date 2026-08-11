/// Runs a ``Plan`` one step at a time, authorizing each step immediately before it would
/// execute, and stops at the first step that is not cleared to run unattended.
///
/// The halt-on-first-gate behavior is the point: it turns a plan into the Observe →
/// Assist → Confirm loop. Read-only and advisory steps stream through; the moment a step
/// needs confirmation (or is blocked) the run pauses and reports it, so the caller can
/// ask the user "do you want me to do this?" and, once approved, resume from there. An
/// executor failure also halts the run — later steps are reported as skipped rather than
/// attempted on a broken foundation.
@MainActor
public struct SequentialPlanOrchestrator {
    private let authorizer: any StepAuthorizing
    private let executor: any StepExecuting

    public init(authorizer: any StepAuthorizing, executor: any StepExecuting) {
        self.authorizer = authorizer
        self.executor = executor
    }

    public func run(_ plan: Plan) async -> OrchestrationResult {
        var reports: [StepReport] = []
        var halted = false

        for step in plan.steps {
            guard !halted else {
                reports.append(
                    StepReport(step: step, authorization: .blocked("A previous step stopped the run."), status: .skipped)
                )
                continue
            }

            let authorization = await authorizer.authorize(step, in: plan.goal)
            switch authorization {
            case .autopilot:
                do {
                    let outcome = try await executor.execute(step)
                    reports.append(StepReport(step: step, authorization: authorization, status: .ran(summary: outcome.summary)))
                } catch {
                    reports.append(StepReport(step: step, authorization: authorization, status: .failed(String(describing: error))))
                    halted = true
                }
            case .needsConfirmation:
                reports.append(StepReport(step: step, authorization: authorization, status: .pausedForConfirmation))
                halted = true
            case .blocked:
                reports.append(StepReport(step: step, authorization: authorization, status: .blocked))
                halted = true
            }
        }

        return OrchestrationResult(plan: plan, reports: reports)
    }
}
