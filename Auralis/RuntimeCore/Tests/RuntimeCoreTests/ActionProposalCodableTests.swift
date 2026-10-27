import AuralisFoundation
import Foundation
@testable import RuntimeCore
import Testing

@Suite("ActionProposal")
struct ActionProposalCodableTests {
    @Test
    func roundTripsThroughJSON() throws {
        let proposal = ActionProposal(
            actor: .human,
            intent: "Sign a message for login",
            capability: .signMessage,
            impact: .highRisk,
            requiredApprovals: ["owner"],
            requiredCheckIDs: ["address.valid", "chain.inScope"],
            correlationID: "session-123"
        )

        let data = try JSONEncoder().encode(proposal)
        let decoded = try JSONDecoder().decode(ActionProposal.self, from: data)

        #expect(decoded == proposal)
    }

    @Test
    func distinctIdentitiesAreNotEqual() {
        let a = ActionProposal(actor: .system, intent: "x", capability: .runPlugin, impact: .externalImpact)
        let b = ActionProposal(actor: .system, intent: "x", capability: .runPlugin, impact: .externalImpact)
        #expect(a != b)
    }

    @Test("correlated proposals carry an explicit workflow and pending authority")
    func attributionContextIsExplicit() {
        let proposal = ActionProposal(
            actor: ActorRef(kind: .workflow, identifier: "planner.daily"),
            intent: "Prepare the daily plan",
            capability: .runPlugin,
            impact: .readOnly,
            correlationID: "run-123"
        )

        #expect(proposal.workflowRun == .workflow(id: "run-123", workflowID: nil))
        #expect(proposal.authorityState == .pending)
        #expect(proposal.resolvedCorrelationID == "run-123")
    }

    @Test("standalone proposals receive a stable explicit workflow reference")
    func standaloneAttributionIsStable() {
        let proposal = ActionProposal(
            actor: .human,
            intent: "Inspect local state",
            capability: .runPlugin,
            impact: .readOnly
        )

        #expect(proposal.workflowRun == .standalone(actionID: proposal.id))
        #expect(proposal.resolvedCorrelationID == proposal.id.uuidString)
    }
}
