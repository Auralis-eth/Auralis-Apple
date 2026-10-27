import AuralisFoundation
import Foundation

public enum CommitmentAmendment: Equatable, Sendable {
    case priority(CommitmentPriority)
    case constraints([String])
    case expiration(Date?)
}

public enum CommitmentFulfillmentEvidence: Equatable, Sendable {
    case confirmed(references: [String])
    case absent
    case contradicted(references: [String])
}

public struct CommitmentLifecycle: Sendable {
    public init() {}

    public func amend(
        _ commitment: Commitment,
        amendment: CommitmentAmendment,
        by principalID: PrincipalID,
        at date: Date,
        reason: String
    ) throws -> Commitment {
        try requireOpen(commitment)
        var priority = commitment.priority
        var constraints = commitment.constraints
        var expiration = commitment.expiresAt
        switch amendment {
        case .priority(let value): priority = value
        case .constraints(let value): constraints = value
        case .expiration(let value):
            if let value, value <= date { throw CommitmentError.invalidExpiration }
            expiration = value
        }
        return replacing(
            commitment,
            priority: priority,
            constraints: constraints,
            expiresAt: expiration,
            transition: transition(.amended, by: principalID, at: date, reason: reason)
        )
    }

    public func cancel(
        _ commitment: Commitment,
        by principalID: PrincipalID,
        at date: Date,
        reason: String
    ) throws -> Commitment {
        try requireOpen(commitment)
        return replacing(
            commitment,
            status: .cancelled,
            transition: transition(.cancelled, by: principalID, at: date, reason: reason)
        )
    }

    public func delegate(
        _ commitment: Commitment,
        to assignee: PrincipalID,
        by principalID: PrincipalID,
        at date: Date,
        reason: String
    ) throws -> Commitment {
        try requireOpen(commitment)
        return replacing(
            commitment,
            status: .delegated,
            assignee: assignee,
            transition: transition(.delegated, by: principalID, at: date, reason: reason)
        )
    }

    public func escalate(
        _ commitment: Commitment,
        by principalID: PrincipalID,
        at date: Date,
        reason: String
    ) throws -> Commitment {
        try requireOpen(commitment)
        return replacing(
            commitment,
            status: .escalated,
            transition: transition(.escalated, by: principalID, at: date, reason: reason)
        )
    }

    public func expireIfNeeded(
        _ commitment: Commitment,
        at date: Date,
        by principalID: PrincipalID
    ) throws -> Commitment {
        try requireOpen(commitment)
        guard let expiresAt = commitment.expiresAt, date >= expiresAt else { return commitment }
        return replacing(
            commitment,
            status: .expired,
            transition: transition(.expired, by: principalID, at: date, reason: "Commitment expired")
        )
    }

    public func fulfill(
        _ commitment: Commitment,
        evidence: CommitmentFulfillmentEvidence,
        by principalID: PrincipalID,
        at date: Date
    ) throws -> Commitment {
        try requireOpen(commitment)
        guard case .confirmed(let references) = evidence, !references.isEmpty else {
            throw CommitmentError.verificationRequired
        }
        return replacing(
            commitment,
            status: .fulfilled,
            transition: transition(
                .fulfilled,
                by: principalID,
                at: date,
                reason: "Outcome verified",
                evidenceReferences: references
            )
        )
    }

    private func requireOpen(_ commitment: Commitment) throws {
        if commitment.status.isTerminal { throw CommitmentError.terminalCommitment }
    }

    private func transition(
        _ kind: CommitmentTransitionKind,
        by principalID: PrincipalID,
        at date: Date,
        reason: String,
        evidenceReferences: [String] = []
    ) -> CommitmentTransition {
        CommitmentTransition(
            kind: kind,
            recordedAt: date,
            principalID: principalID,
            reason: reason,
            evidenceReferences: evidenceReferences
        )
    }

    private func replacing(
        _ value: Commitment,
        priority: CommitmentPriority? = nil,
        constraints: [String]? = nil,
        status: CommitmentStatus? = nil,
        assignee: PrincipalID? = nil,
        expiresAt: Date?? = nil,
        transition: CommitmentTransition
    ) -> Commitment {
        Commitment(
            id: value.id,
            intentID: value.intentID,
            summary: value.summary,
            outcome: value.outcome,
            priority: priority ?? value.priority,
            constraints: constraints ?? value.constraints,
            dependencies: value.dependencies,
            authorization: value.authorization,
            status: status ?? value.status,
            assignee: assignee ?? value.assignee,
            expiresAt: expiresAt ?? value.expiresAt,
            transitions: value.transitions + [transition]
        )
    }
}
