import Foundation

/// The product of a successful tool execution.
public struct ToolCallArtifact: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let toolID: String
    public let summary: String
    public let outputFields: [String: String]

    public init(
        id: UUID = UUID(),
        toolID: String,
        summary: String,
        outputFields: [String: String] = [:]
    ) {
        self.id = id
        self.toolID = toolID
        self.summary = summary
        self.outputFields = outputFields
    }
}

/// An unforgeable capability proving that registry resolution and before-call governance completed.
/// Only RuntimeCore can create one, so conforming executors cannot be invoked directly by app code.
public struct ToolExecutionAuthorization: Sendable {
    public let toolID: String
    public let proposalID: UUID
}

/// Performs the real work of a cleared tool call. Injected into the pipeline so execution stays
/// separable from governance (and so tests can supply a fake).
public protocol ToolExecuting: Sendable {
    func execute(
        _ tool: ToolDefinition,
        proposal: ActionProposal,
        authorization: ToolExecutionAuthorization
    ) async throws -> ToolCallArtifact
}

/// The terminal state of a run through the governed pipeline.
public enum ToolCallOutcome: Equatable, Sendable {
    case executed(ToolCallArtifact)
    case blocked(reason: String)
    case needsRevision(instructions: String)
    case needsApproval(ApprovalRequest)
    case failed(reason: String)
    /// The underlying action reached `original`, but one or more mandatory governance evidence
    /// emissions failed. Keeping both facts prevents callers from mistaking an executed action for
    /// an execution failure or silently accepting an unreceipted decision.
    case evidenceIncomplete(original: EvidenceOutcome, failures: [String])

    var failureReason: String {
        guard case let .failed(reason) = self else {
            return "Tool execution failed."
        }
        return reason
    }
}

public enum EvidenceOutcome: Equatable, Sendable {
    case executed(ToolCallArtifact)
    case blocked(reason: String)
    case needsRevision(instructions: String)
    case needsApproval(ApprovalRequest)
    case failed(reason: String)

    /// Why the underlying run did not succeed, for callers holding an `.evidenceIncomplete` outcome
    /// that need to report the original verdict alongside the evidence failures.
    var failureReason: String {
        switch self {
        case .executed:
            return "Tool execution succeeded."
        case let .blocked(reason):
            return reason
        case let .needsRevision(instructions):
            return instructions
        case .needsApproval:
            return "Awaiting human approval."
        case let .failed(reason):
            return reason
        }
    }
}
