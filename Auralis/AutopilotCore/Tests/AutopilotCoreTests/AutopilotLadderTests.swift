import CapabilitiesCore
import PlannerCore
import PolicyCore
import Testing
@testable import AutopilotCore

/// A gate backed by the *real* PolicyCore evaluation in Observe mode — the shipping app's
/// current posture. Proves the whole stack composes against actual policy, not a stub.
private struct ObserveModeGate: PolicyActionGating {
    func attempt(_ action: PolicyControlledAction) async -> PolicyGateResult {
        await ActionPolicyGate.attempt(action, mode: .observe)
    }
}

/// Executes by recording the step; used to confirm which steps actually ran.
@MainActor
private final class RecordingExecutor: StepExecuting {
    private(set) var executed: [PlanStep] = []
    func execute(_ step: PlanStep) async throws -> StepExecutionOutcome {
        executed.append(step)
        return StepExecutionOutcome(summary: "ran \(step.title)")
    }
}

@MainActor
struct AutopilotLadderTests {
    @Test("in Observe mode a real goal runs its read-only steps then stops at the state change")
    func observeModeRunsReadThenBlocks() async {
        let executor = RecordingExecutor()
        let runner = AutopilotRunner(
            planner: DeterministicGoalPlanner(),
            authorizer: AutopilotAuthorizer(gate: ObserveModeGate()),
            executor: executor
        )

        let (plan, result) = await runner.run(PlanningGoal(text: "organize my music library"))

        // The plan is observe → assist → execute.
        #expect(plan.steps.map(\.kind) == [.observe, .assist, .execute])
        // Only the read-only and advisory steps ran; the execute step was blocked by policy.
        #expect(executor.executed.map(\.kind) == [.observe, .assist])
        #expect(result.isComplete == false)

        guard case .blocked = result.reports.last?.status else {
            Issue.record("expected the execute step to be blocked in Observe mode")
            return
        }
    }

    @Test("marking a routine trusted still cannot run a state change while policy is in Observe mode")
    func trustedRoutineStillBlockedInObserveMode() async {
        let executor = RecordingExecutor()
        let runner = AutopilotRunner(
            planner: DeterministicGoalPlanner(),
            authorizer: AutopilotAuthorizer(
                gate: ObserveModeGate(),
                trustedRoutines: TrustedRoutineAllowlist([.autoOrganization])
            ),
            executor: executor
        )

        let (_, result) = await runner.run(PlanningGoal(text: "organize my music library"))

        #expect(executor.executed.map(\.kind) == [.observe, .assist])
        guard case .blocked = result.reports.last?.status else {
            Issue.record("trust must not bypass the Observe-mode policy block")
            return
        }
    }
}
