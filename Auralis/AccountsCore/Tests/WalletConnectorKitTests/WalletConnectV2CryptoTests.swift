import CryptoKit
import Foundation
import Testing
@testable import WalletConnectorKit

/// Parity tests pinning the WalletConnect v2 primitives to the reference
/// implementation (reown-swift `WalletConnectKMS`). Vectors are copied from
/// `Tests/WalletConnectKMSTests/CryptoTestData.swift` and `EnvelopeTests.swift`.
@Suite("WalletConnect v2 crypto")
struct WalletConnectV2CryptoTests {
    // From reown CryptoTestData.
    static let privateKeyA = "1fb63fca5c6ac731246f2f069d3bc2454345d5208254aa8ea7bffc6d110c8862"
    static let publicKeyB = "590c2c627be7af08597091ff80dd41f7fa28acd10ef7191d7e830e116d3a186a"
    static let expectedSharedKey = "0653ca620c7b4990392e1c53c4a51c14a2840cd20f0f1524cf435b17b6fe988c"

    @Test("X25519 + HKDF-SHA256 matches the reference shared key")
    func derivesSharedKey() throws {
        let privData = try #require(WalletConnectV2Crypto.data(hexEncoded: Self.privateKeyA))
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privData)
        let derived = try WalletConnectV2Crypto.deriveSymmetricKey(privateKey: priv, peerPublicKeyHex: Self.publicKeyB)
        #expect(WalletConnectV2Crypto.hexString(derived) == Self.expectedSharedKey)
    }

    @Test("Type0 envelope parses the reference vector")
    func parsesType0Envelope() throws {
        let envelope = try WalletConnectEnvelope(base64Encoded: "AFdhbGxldENvbm5lY3Q=")
        #expect(envelope.type == .type0)
        #expect(String(data: envelope.sealbox, encoding: .utf8) == "WalletConnect")
    }

    @Test("Type1 envelope round-trips the sender public key")
    func roundTripsType1Envelope() throws {
        let pub = try #require(WalletConnectV2Crypto.data(hexEncoded: "f82388e76d53632d8c73e4f4dbfe122321affee5d79cb63ee804a4ef251f4219"))
        let sealbox = try #require(Data(base64Encoded: "V2FsbGV0Q29ubmVjdA=="))
        let envelope = WalletConnectEnvelope(type: .type1(senderPublicKey: pub), sealbox: sealbox)
        let decoded = try WalletConnectEnvelope(base64Encoded: envelope.base64EncodedString())
        #expect(decoded.type == .type1(senderPublicKey: pub))
        #expect(decoded.sealbox == sealbox)
    }

    @Test("ChaCha20-Poly1305 seal/open round-trips")
    func sealsAndOpens() throws {
        let symKey = try #require(WalletConnectV2Crypto.data(hexEncoded: Self.expectedSharedKey))
        let plaintext = Data("hello wallet".utf8)
        let sealbox = try WalletConnectV2Crypto.seal(plaintext: plaintext, symKey: symKey)
        // nonce(12) + ciphertext(12) + tag(16)
        #expect(sealbox.count == plaintext.count + 28)
        let opened = try WalletConnectV2Crypto.open(sealbox: sealbox, symKey: symKey)
        #expect(opened == plaintext)
    }

    @Test("Opening a tampered sealbox fails authentication")
    func rejectsTamperedSealbox() throws {
        let symKey = try #require(WalletConnectV2Crypto.data(hexEncoded: Self.expectedSharedKey))
        var sealbox = try WalletConnectV2Crypto.seal(plaintext: Data("secret".utf8), symKey: symKey)
        sealbox[sealbox.count - 1] ^= 0xFF
        #expect(throws: WalletConnectionError.self) {
            _ = try WalletConnectV2Crypto.open(sealbox: sealbox, symKey: symKey)
        }
    }

    @Test("Malformed envelope strings are rejected")
    func rejectsMalformedEnvelope() {
        #expect(throws: WalletConnectEnvelope.Errors.self) {
            _ = try WalletConnectEnvelope(base64Encoded: "not base64!!!")
        }
    }
}
