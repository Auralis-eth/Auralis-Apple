import Foundation

/// A request for a human (or higher authority) to approve a specific proposal.
///
/// Produced when a ``JudgeDecision`` escalates. Kept minimal on purpose: it pairs the exact proposal
/// under review with the prompt the approval surface should show.
public struct ApprovalRequest: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let proposal: ActionProposal
    public let prompt: String

    public init(id: UUID = UUID(), proposal: ActionProposal, prompt: String) {
        self.id = id
        self.proposal = proposal
        self.prompt = prompt
    }
}

/// The verdict a Judge returns for an ``ActionProposal``.
///
/// This is the richer successor to the binary `PolicyGateResult` and the three-way
/// `StepAuthorization` ladder. The two new cases — `revise` and `escalate` — are the whole point:
/// governance can now send a proposal back for correction, or hand it up for approval, instead of
/// only allowing or blocking it.
///
/// RuntimeCore stays a leaf package, so the mappings from `JudgeDecision` onto `StepAuthorization`
/// (PlannerCore) and `PolicyGateResult` (PolicyCore) live in those higher layers, not here.
public enum JudgeDecision: Equatable, Sendable, Codable {
    /// Permit the action to proceed.
    case allow

    /// Refuse the action, with a user-facing reason.
    case block(reason: String)

    /// Send the proposal back to its author with instructions on how to make it acceptable.
    case revise(instructions: String)

    /// Defer to an approval authority before the action may proceed.
    case escalate(approvalRequest: ApprovalRequest)

    /// Whether this verdict permits execution without any further input.
    public var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }
}
