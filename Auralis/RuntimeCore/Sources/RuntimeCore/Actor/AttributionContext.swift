import Foundation

/// The workflow boundary that owns an action and its resulting evidence.
/// Standalone work is explicit rather than represented by an absent correlation identifier.
public enum WorkflowRunRef: Equatable, Hashable, Sendable, Codable {
    case workflow(id: String, workflowID: String?)
    case standalone(actionID: UUID)

    public var correlationID: String {
        switch self {
        case let .workflow(id, _): id
        case let .standalone(actionID): actionID.uuidString
        }
    }

    public static func resolved(
        correlationID: String?,
        workflowID: String? = nil,
        fallbackActionID: UUID
    ) -> WorkflowRunRef {
        guard let correlationID, correlationID.isEmpty == false else {
            return .standalone(actionID: fallbackActionID)
        }
        return .workflow(id: correlationID, workflowID: workflowID)
    }
}

/// The authorization lifecycle for an attributed action.
public enum AuthorityState: Equatable, Sendable, Codable {
    case pending
    case resolved(AuthorityRef)
    case denied(reason: String)
    case notApplicable(reason: String)
    case legacyUnknown
}
