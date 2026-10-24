import Foundation
@testable import RuntimeCore
import Testing

@Suite("ReceiptSigner")
struct ReceiptSignerTests {
    @Test
    func signsAndVerifiesRoundTrip() async throws {
        let signer = SoftwareReceiptSigner()
        let signature = try await signer.sign("chainhash-abc123")
        #expect(signer.verify("chainhash-abc123", signature: signature))
    }

    @Test
    func rejectsTamperedMessage() async throws {
        let signer = SoftwareReceiptSigner()
        let signature = try await signer.sign("chainhash-abc123")
        #expect(signer.verify("chainhash-TAMPERED", signature: signature) == false)
    }

    @Test
    func externalVerifierUsesEmbeddedPublicKey() async throws {
        // A verifier with no signer instance can still validate from the exported signature.
        let signature = try await SoftwareReceiptSigner().sign("head-hash")
        #expect(SoftwareReceiptSigner.verifyStatic("head-hash", signature: signature))
        #expect(SoftwareReceiptSigner.verifyStatic("other", signature: signature) == false)
    }

    @Test
    func signatureRoundTripsThroughJSON() async throws {
        let signature = try await SoftwareReceiptSigner().sign("m")
        let data = try JSONEncoder().encode(signature)
        let decoded = try JSONDecoder().decode(ReceiptSignature.self, from: data)
        #expect(decoded == signature)
    }
}
