import AuralisFoundation
import CommitmentCore
import EvalCore
import Foundation
import IntentCore
import OutcomeVerification
import RuntimeCore
import Testing

@Suite("Commitment outcome verification")
struct OutcomeVerificationTests {
    @Test("Missing, contradictory, and confirmed evidence are deterministic")
    func verificationStates() throws {
        let principal = try #require(PrincipalID(rawValue: "human:owner"))
        let intent = Intent(summary: "Finish", desiredOutcome: "Verified", source: .explicitHuman)
            .authorized(by: principal, evidenceReference: "approval:1")
        let commitment = try CommitmentFactory().create(
            from: intent,
            outcome: OutcomeSpec(summary: "Verified", criteria: [.producedArtifact])
        )
        let verifier = CommitmentOutcomeVerifier()

        let missing = verifier.verify(commitment: commitment, evaluation: nil, evidenceReferences: [])
        let failed = EvalResult(
            outcomeID: commitment.outcome.id,
            correlationID: "run:1",
            results: [],
            grade: .failed
        )
        let contradicted = verifier.verify(
            commitment: commitment,
            evaluation: failed,
            evidenceReferences: ["receipt:failure"]
        )
        let passed = EvalResult(
            outcomeID: commitment.outcome.id,
            correlationID: "run:2",
            results: [],
            grade: .passed
        )
        let confirmed = verifier.verify(
            commitment: commitment,
            evaluation: passed,
            evidenceReferences: ["receipt:confirmation"]
        )

        #expect(missing.status == .evidenceMissing)
        #expect(contradicted.status == .contradicted)
        #expect(confirmed.status == .confirmed)
        #expect(confirmed.fulfillmentEvidence == .confirmed(references: ["receipt:confirmation"]))
    }

    @Test("A grade for another outcome cannot close the commitment")
    func outcomeIdentityMustMatch() throws {
        let principal = try #require(PrincipalID(rawValue: "human:owner"))
        let commitment = try CommitmentFactory().create(
            from: Intent(summary: "Finish", desiredOutcome: "Verified", source: .explicitHuman)
                .authorized(by: principal, evidenceReference: "approval:1"),
            outcome: OutcomeSpec(summary: "Verified")
        )
        let unrelated = EvalResult(
            outcomeID: UUID(),
            correlationID: "run:other",
            results: [],
            grade: .passed
        )

        let result = CommitmentOutcomeVerifier().verify(
            commitment: commitment,
            evaluation: unrelated,
            evidenceReferences: ["receipt:other"]
        )
        #expect(result.status == .evidenceMissing)
    }
}
