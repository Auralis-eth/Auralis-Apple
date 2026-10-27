import CommitmentCore
import EvalCore
import Foundation

public enum CommitmentVerificationStatus: String, Equatable, Codable, Sendable {
    case confirmed
    case contradicted
    case evidenceMissing = "evidence_missing"
}

public struct CommitmentVerification: Equatable, Codable, Sendable {
    public let commitmentID: CommitmentID
    public let outcomeID: UUID
    public let evaluationID: UUID?
    public let status: CommitmentVerificationStatus
    public let evidenceReferences: [String]
    public let verifiedAt: Date

    public init(
        commitmentID: CommitmentID,
        outcomeID: UUID,
        evaluationID: UUID?,
        status: CommitmentVerificationStatus,
        evidenceReferences: [String],
        verifiedAt: Date
    ) {
        self.commitmentID = commitmentID
        self.outcomeID = outcomeID
        self.evaluationID = evaluationID
        self.status = status
        self.evidenceReferences = evidenceReferences
        self.verifiedAt = verifiedAt
    }

    public var fulfillmentEvidence: CommitmentFulfillmentEvidence {
        switch status {
        case .confirmed:
            .confirmed(references: evidenceReferences)
        case .contradicted:
            .contradicted(references: evidenceReferences)
        case .evidenceMissing:
            .absent
        }
    }
}

public struct CommitmentOutcomeVerifier: Sendable {
    public init() {}

    public func verify(
        commitment: Commitment,
        evaluation: EvalResult?,
        evidenceReferences: [String],
        at date: Date = .now
    ) -> CommitmentVerification {
        guard let evaluation,
              evaluation.outcomeID == commitment.outcome.id,
              !evidenceReferences.isEmpty else {
            return CommitmentVerification(
                commitmentID: commitment.id,
                outcomeID: commitment.outcome.id,
                evaluationID: evaluation?.id,
                status: .evidenceMissing,
                evidenceReferences: evidenceReferences,
                verifiedAt: date
            )
        }

        let status: CommitmentVerificationStatus = switch evaluation.grade {
        case .passed: .confirmed
        case .failed: .contradicted
        case .inconclusive: .evidenceMissing
        }
        return CommitmentVerification(
            commitmentID: commitment.id,
            outcomeID: commitment.outcome.id,
            evaluationID: evaluation.id,
            status: status,
            evidenceReferences: evidenceReferences,
            verifiedAt: date
        )
    }
}
