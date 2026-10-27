import AuralisFoundation
import Foundation
import IntentCore
import RuntimeCore

public struct CommitmentID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

public enum CommitmentPriority: String, CaseIterable, Codable, Sendable {
    case low
    case normal
    case high
    case critical
}

public enum CommitmentStatus: String, Codable, Sendable {
    case active
    case cancelled
    case delegated
    case expired
    case escalated
    case fulfilled

    public var isTerminal: Bool {
        switch self {
        case .cancelled, .delegated, .expired, .fulfilled:
            true
        case .active, .escalated:
            false
        }
    }
}

public enum CommitmentTransitionKind: String, Codable, Sendable {
    case created
    case amended
    case cancelled
    case delegated
    case expired
    case escalated
    case fulfilled
}

public struct CommitmentTransition: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let kind: CommitmentTransitionKind
    public let recordedAt: Date
    public let principalID: PrincipalID
    public let reason: String
    public let evidenceReferences: [String]

    public init(
        id: UUID = UUID(),
        kind: CommitmentTransitionKind,
        recordedAt: Date,
        principalID: PrincipalID,
        reason: String,
        evidenceReferences: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.recordedAt = recordedAt
        self.principalID = principalID
        self.reason = reason
        self.evidenceReferences = evidenceReferences
    }
}

public struct Commitment: Identifiable, Equatable, Codable, Sendable {
    public let id: CommitmentID
    public let intentID: IntentID
    public let summary: String
    public let outcome: OutcomeSpec
    public let priority: CommitmentPriority
    public let constraints: [String]
    public let dependencies: [CommitmentID]
    public let authorization: IntentAuthorization
    public let status: CommitmentStatus
    public let assignee: PrincipalID?
    public let expiresAt: Date?
    public let transitions: [CommitmentTransition]

    public init(
        id: CommitmentID,
        intentID: IntentID,
        summary: String,
        outcome: OutcomeSpec,
        priority: CommitmentPriority,
        constraints: [String],
        dependencies: [CommitmentID],
        authorization: IntentAuthorization,
        status: CommitmentStatus,
        assignee: PrincipalID?,
        expiresAt: Date?,
        transitions: [CommitmentTransition]
    ) {
        self.id = id
        self.intentID = intentID
        self.summary = summary
        self.outcome = outcome
        self.priority = priority
        self.constraints = constraints
        self.dependencies = dependencies
        self.authorization = authorization
        self.status = status
        self.assignee = assignee
        self.expiresAt = expiresAt
        self.transitions = transitions
    }
}

public enum CommitmentError: Error, Equatable, Sendable {
    case authorizationRequired
    case terminalCommitment
    case verificationRequired
    case invalidExpiration
}

public struct CommitmentFactory: Sendable {
    public init() {}

    public func create(
        from intent: Intent,
        outcome: OutcomeSpec,
        priority: CommitmentPriority = .normal,
        constraints: [String] = [],
        dependencies: [CommitmentID] = [],
        expiresAt: Date? = nil,
        id: CommitmentID = CommitmentID(rawValue: UUID()),
        transitionID: UUID = UUID()
    ) throws -> Commitment {
        guard let authorization = intent.authorization else {
            throw CommitmentError.authorizationRequired
        }
        if let expiresAt, expiresAt <= authorization.authorizedAt {
            throw CommitmentError.invalidExpiration
        }

        return Commitment(
            id: id,
            intentID: intent.id,
            summary: intent.summary,
            outcome: outcome,
            priority: priority,
            constraints: constraints,
            dependencies: dependencies,
            authorization: authorization,
            status: .active,
            assignee: nil,
            expiresAt: expiresAt,
            transitions: [
                CommitmentTransition(
                    id: transitionID,
                    kind: .created,
                    recordedAt: authorization.authorizedAt,
                    principalID: authorization.principalID,
                    reason: "Authorized commitment created",
                    evidenceReferences: [authorization.evidenceReference]
                )
            ]
        )
    }
}
