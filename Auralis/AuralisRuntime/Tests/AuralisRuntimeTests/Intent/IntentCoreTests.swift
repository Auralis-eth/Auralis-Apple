import AuralisFoundation
import Foundation
import AuralisRuntime
import Testing

@Suite("Intent authorization")
struct IntentCoreTests {
    @Test("Inferred intent remains unauthorized until an explicit transition")
    func inferredIntentRequiresAuthorization() throws {
        let intent = Intent(
            summary: "Keep Thursday free",
            desiredOutcome: "No commitments Thursday afternoon",
            source: .inferred,
            capturedAt: Date(timeIntervalSince1970: 10)
        )

        #expect(intent.authorization == nil)

        let principal = try #require(PrincipalID(rawValue: "human:daniel"))
        let authorized = intent.authorized(
            by: principal,
            at: Date(timeIntervalSince1970: 20),
            evidenceReference: "approval:42"
        )

        #expect(authorized.source == .inferred)
        #expect(authorized.authorization?.principalID == principal)
        #expect(authorized.authorization?.evidenceReference == "approval:42")
    }
}
