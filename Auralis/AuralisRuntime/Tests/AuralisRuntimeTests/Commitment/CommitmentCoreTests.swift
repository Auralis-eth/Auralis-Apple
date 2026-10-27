import AuralisFoundation
import AuralisRuntime
import Foundation
import Testing

@Suite("Commitment lifecycle")
struct CommitmentCoreTests {
    @Test("Unauthorized intent cannot become a commitment")
    func authorizationBoundary() throws {
        let intent = Intent(summary: "Ship", desiredOutcome: "Released", source: .inferred)

        #expect(throws: CommitmentError.authorizationRequired) {
            try CommitmentFactory().create(from: intent, outcome: OutcomeSpec(summary: "Released"))
        }
    }

    @Test("Dependencies, idempotency identity, and lifecycle survive serialization")
    func lifecycleRoundTrip() throws {
        let principal = try #require(PrincipalID(rawValue: "human:owner"))
        let intent = Intent(summary: "Ship safely", desiredOutcome: "Verified release", source: .explicitHuman)
            .authorized(
                by: principal,
                at: Date(timeIntervalSince1970: 100),
                evidenceReference: "approval:release"
            )
        let dependency = CommitmentID(rawValue: UUID())
        let commitment = try CommitmentFactory().create(
            from: intent,
            outcome: OutcomeSpec(summary: "Release verified", criteria: [.producedArtifact]),
            priority: .high,
            constraints: ["No unreviewed deployment"],
            dependencies: [dependency],
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )
        let amended = try CommitmentLifecycle().amend(
            commitment,
            amendment: .priority(.critical),
            by: principal,
            at: Date(timeIntervalSince1970: 200),
            reason: "Release window opened"
        )
        let decoded = try JSONDecoder().decode(
            Commitment.self,
            from: JSONEncoder().encode(amended)
        )

        #expect(decoded == amended)
        #expect(decoded.id == commitment.id)
        #expect(decoded.dependencies == [dependency])
        #expect(decoded.transitions.map(\.kind) == [.created, .amended])
    }

    @Test("Successful execution evidence does not fulfill without outcome confirmation")
    func fulfillmentRequiresVerification() throws {
        let principal = try #require(PrincipalID(rawValue: "human:owner"))
        let commitment = try makeCommitment(principal: principal)
        let lifecycle = CommitmentLifecycle()

        #expect(throws: CommitmentError.verificationRequired) {
            try lifecycle.fulfill(
                commitment,
                evidence: .absent,
                by: principal,
                at: Date(timeIntervalSince1970: 300)
            )
        }
        #expect(throws: CommitmentError.verificationRequired) {
            try lifecycle.fulfill(
                commitment,
                evidence: .contradicted(references: ["receipt:tool-succeeded"]),
                by: principal,
                at: Date(timeIntervalSince1970: 300)
            )
        }

        let fulfilled = try lifecycle.fulfill(
            commitment,
            evidence: .confirmed(references: ["verification:outcome-7"]),
            by: principal,
            at: Date(timeIntervalSince1970: 301)
        )
        #expect(fulfilled.status == .fulfilled)
    }

    @Test("Cancellation, delegation, expiration, and escalation are explicit transitions")
    func lifecycleTransitions() throws {
        let principal = try #require(PrincipalID(rawValue: "human:owner"))
        let delegate = try #require(PrincipalID(rawValue: "agent:delegate"))
        let base = try makeCommitment(principal: principal)
        let lifecycle = CommitmentLifecycle()

        let cancelled = try lifecycle.cancel(base, by: principal, at: .now, reason: "No longer needed")
        let delegated = try lifecycle.delegate(base, to: delegate, by: principal, at: .now, reason: "Specialist")
        let escalated = try lifecycle.escalate(base, by: principal, at: .now, reason: "Needs judgment")
        let expiring = try lifecycle.amend(
            base,
            amendment: .expiration(Date(timeIntervalSince1970: 500)),
            by: principal,
            at: Date(timeIntervalSince1970: 200),
            reason: "Set deadline"
        )
        let expired = try lifecycle.expireIfNeeded(
            expiring,
            at: Date(timeIntervalSince1970: 501),
            by: principal
        )

        #expect(cancelled.status == .cancelled)
        #expect(delegated.status == .delegated)
        #expect(delegated.assignee == delegate)
        #expect(escalated.status == .escalated)
        #expect(expired.status == .expired)
        #expect(throws: CommitmentError.terminalCommitment) {
            try lifecycle.cancel(cancelled, by: principal, at: .now, reason: "Again")
        }
    }

    private func makeCommitment(principal: PrincipalID) throws -> Commitment {
        let intent = Intent(
            summary: "Complete outcome",
            desiredOutcome: "Evidence confirms completion",
            source: .explicitHuman
        ).authorized(
            by: principal,
            at: Date(timeIntervalSince1970: 100),
            evidenceReference: "approval:1"
        )
        return try CommitmentFactory().create(
            from: intent,
            outcome: OutcomeSpec(summary: "Verified", criteria: [.producedArtifact])
        )
    }
}
