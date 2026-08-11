import CapabilitiesCore
import Testing
@testable import PlannerCore

/// Authorizes steps from a fixed verdict-by-kind table, so tests can drive each ladder rung.
@MainActor
private struct StubAuthorizer: StepAuthorizing {
    var verdicts: [PlanStepKind: StepAuthorization]

    func authorize(_ step: PlanStep, in goal: PlanningGoal) async -> StepAuthorization {
        verdicts[step.kind] ?? .blocked("no verdict")
    }
}

/// Records what it was asked to execute and returns a summary (or throws when told to).
@MainActor
private final class RecordingExecutor: StepExecuting {
    private(set) var executed: [PlanStep] = []
    var failOn: CapabilityID?

    struct BoomError: Error {}

    func execute(_ step: PlanStep) async throws -> StepExecutionOutcome {
        if step.capability == failOn { throw BoomError() }
        executed.append(step)
        return StepExecutionOutcome(summary: "did \(step.title)")
    }
}

private func threeStepPlan() -> Plan {
    Plan(
        goal: PlanningGoal(text: "demo"),
        steps: [
            PlanStep(capability: .musicLibraryClassification, kind: .observe, title: "look", rationale: "r"),
            PlanStep(capability: .autoOrganization, kind: .assist, title: "suggest", rationale: "r"),
            PlanStep(capability: .autoOrganization, kind: .execute, title: "apply", rationale: "r"),
        ],
        summary: "demo plan"
    )
}

@MainActor
struct SequentialPlanOrchestratorTests {
    @Test("runs observe and assist unattended, then pauses at an execute step needing confirmation")
    func pausesAtConfirmation() async {
        let authorizer = StubAuthorizer(verdicts: [
            .observe: .autopilot,
            .assist: .autopilot,
            .execute: .needsConfirmation("confirm?"),
        ])
        let executor = RecordingExecutor()
        let result = await SequentialPlanOrchestrator(authorizer: authorizer, executor: executor).run(threeStepPlan())

        #expect(executor.executed.map(\.kind) == [.observe, .assist])
        #expect(result.pendingConfirmation?.kind == .execute)
        #expect(result.isComplete == false)
    }

    @Test("a blocked step halts the run and later steps are skipped, not attempted")
    func blockedHaltsRun() async {
        let authorizer = StubAuthorizer(verdicts: [
            .observe: .autopilot,
            .assist: .blocked("nope"),
            .execute: .autopilot,
        ])
        let executor = RecordingExecutor()
        let result = await SequentialPlanOrchestrator(authorizer: authorizer, executor: executor).run(threeStepPlan())

        #expect(executor.executed.map(\.kind) == [.observe])
        #expect(result.reports.map(\.status) == [.ran(summary: "did look"), .blocked, .skipped])
    }

    @Test("when every step is autopilot the whole plan runs to completion")
    func fullAutopilotCompletes() async {
        let authorizer = StubAuthorizer(verdicts: [.observe: .autopilot, .assist: .autopilot, .execute: .autopilot])
        let executor = RecordingExecutor()
        let result = await SequentialPlanOrchestrator(authorizer: authorizer, executor: executor).run(threeStepPlan())

        #expect(executor.executed.count == 3)
        #expect(result.isComplete)
        #expect(result.pendingConfirmation == nil)
    }

    @Test("an executor failure halts the run and is reported")
    func executorFailureHalts() async {
        let authorizer = StubAuthorizer(verdicts: [.observe: .autopilot, .assist: .autopilot, .execute: .autopilot])
        let executor = RecordingExecutor()
        executor.failOn = .musicLibraryClassification
        let result = await SequentialPlanOrchestrator(authorizer: authorizer, executor: executor).run(threeStepPlan())

        guard case .failed = result.reports.first?.status else {
            Issue.record("expected first step to fail")
            return
        }
        #expect(result.isComplete == false)
    }
}
