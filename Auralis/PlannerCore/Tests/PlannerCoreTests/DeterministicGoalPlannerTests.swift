import CapabilitiesCore
import Testing
@testable import PlannerCore

struct DeterministicGoalPlannerTests {
    @Test("a recognized goal expands into its template's ordered steps")
    func recognizedGoalUsesTemplate() async {
        let planner = DeterministicGoalPlanner()
        let plan = await planner.makePlan(for: PlanningGoal(text: "Please organize my music library"))

        #expect(plan.capabilities == [.musicLibraryClassification, .autoOrganization, .autoOrganization])
        #expect(plan.steps.map(\.kind) == [.observe, .assist, .execute])
    }

    @Test("planning observes before it executes")
    func observeComesBeforeExecute() async {
        let planner = DeterministicGoalPlanner()
        let plan = await planner.makePlan(for: PlanningGoal(text: "make me a playlist of chill tracks"))

        let firstExecute = plan.steps.firstIndex { $0.kind == .execute }
        let firstObserve = plan.steps.firstIndex { $0.kind == .observe }
        #expect(firstObserve != nil)
        #expect(firstExecute != nil)
        #expect(firstObserve! < firstExecute!)
        #expect(plan.containsStateChange)
    }

    @Test("an unrecognized goal falls back to a single read-only step")
    func unrecognizedGoalIsObserveOnly() async {
        let planner = DeterministicGoalPlanner()
        let plan = await planner.makePlan(for: PlanningGoal(text: "xyzzy nonsense goal"))

        #expect(plan.steps.count == 1)
        #expect(plan.steps.first?.kind == .observe)
        #expect(plan.containsStateChange == false)
    }

    @Test("templates only ever reference capabilities the registry knows")
    func templatesReferenceKnownCapabilities() {
        let known = Set(CapabilityID.allCases)
        for template in PlanTemplateCatalog.builtIn {
            for step in template.steps {
                #expect(known.contains(step.capability), "\(template.id) references unknown \(step.capability)")
            }
        }
    }
}
