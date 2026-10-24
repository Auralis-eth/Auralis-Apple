import CapabilitiesCore
import Foundation
@testable import RuntimeCore
import Testing

@Suite("JudgeDecision")
struct JudgeDecisionTests {
    private func makeProposal() -> ActionProposal {
        ActionProposal(
            actor: .system,
            intent: "Run a plugin",
            capability: .runPlugin,
            impact: .externalImpact
        )
    }

    @Test
    func onlyAllowIsAllowed() {
        #expect(JudgeDecision.allow.isAllowed)
        #expect(!JudgeDecision.block(reason: "denied").isAllowed)
        #expect(!JudgeDecision.revise(instructions: "narrow the scope").isAllowed)
        let request = ApprovalRequest(proposal: makeProposal(), prompt: "Approve?")
        #expect(!JudgeDecision.escalate(approvalRequest: request).isAllowed)
    }

    @Test
    func approvalRequestRoundTripsAndCompares() throws {
        let request = ApprovalRequest(proposal: makeProposal(), prompt: "Approve running this plugin?")

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ApprovalRequest.self, from: data)
        #expect(decoded == request)

        #expect(JudgeDecision.escalate(approvalRequest: request) == .escalate(approvalRequest: request))
        #expect(JudgeDecision.block(reason: "a") != .block(reason: "b"))
    }
}
