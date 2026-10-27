@testable import Auralis
import CryptoKit
import Foundation
import AuralisOperators
import Testing

@Suite("Social envelope cipher")
struct SocialEnvelopeCipherTests {
    private func makeEnvelope() -> SocialEventEnvelope {
        SocialEventEnvelope(
            sessionID: UUID(),
            authorParticipantID: "alice",
            authorCAIP10Account: "eip155:1:0xabc",
            event: .receiptShared(UUID())
        )
    }

    @Test("Seal then open round-trips the envelope under the same key")
    func roundTrips() throws {
        let key = SymmetricKey(size: .bits256)
        let cipher = SocialEnvelopeCipher(sessionKey: key)
        let envelope = makeEnvelope()

        let sealed = try cipher.seal(envelope)
        let opened = try cipher.open(sealed)

        #expect(opened == envelope)
    }

    @Test("Ciphertext is opaque — it does not leak the plaintext envelope")
    func ciphertextIsOpaque() throws {
        let cipher = SocialEnvelopeCipher(sessionKey: SymmetricKey(size: .bits256))
        let envelope = makeEnvelope()

        let sealed = try cipher.seal(envelope)

        #expect(!sealed.contains(envelope.id.uuidString))
        #expect(!sealed.contains(envelope.authorParticipantID))
        // Valid base64 (opaque bytes), not a readable JSON payload.
        #expect(Data(base64Encoded: sealed) != nil)
    }

    @Test("A different key cannot open the payload (fails closed, not silently)")
    func wrongKeyFailsClosed() throws {
        let sealed = try SocialEnvelopeCipher(sessionKey: SymmetricKey(size: .bits256)).seal(makeEnvelope())
        let otherCipher = SocialEnvelopeCipher(sessionKey: SymmetricKey(size: .bits256))

        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try otherCipher.open(sealed)
        }
    }

    @Test("A tampered payload fails authentication")
    func tamperedPayloadFails() throws {
        let cipher = SocialEnvelopeCipher(sessionKey: SymmetricKey(size: .bits256))
        var bytes = try #require(Data(base64Encoded: try cipher.seal(makeEnvelope())))
        bytes[bytes.count - 1] ^= 0xFF // flip the last byte of the auth tag

        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try cipher.open(bytes.base64EncodedString())
        }
    }

    @Test("Non-base64 and garbage payloads fail closed")
    func garbagePayloadFails() throws {
        let cipher = SocialEnvelopeCipher(sessionKey: SymmetricKey(size: .bits256))

        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try cipher.open("not base64 @@@")
        }
        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try cipher.open(Data("too short".utf8).base64EncodedString())
        }
    }

    @Test("Generated session key round-trips base64 → cipher → envelope")
    func generatedKeyRoundTrips() throws {
        let base64Key = SocialSessionKey.generateBase64Encoded()
        let sender = try SocialEnvelopeCipher(base64EncodedSessionKey: base64Key)
        let receiver = try SocialEnvelopeCipher(base64EncodedSessionKey: base64Key)
        let envelope = makeEnvelope()

        #expect(try receiver.open(sender.seal(envelope)) == envelope)
    }

    @Test("Malformed key material fails closed with invalidKey")
    func malformedKeyFailsClosed() {
        #expect(throws: SocialEnvelopeCipherError.invalidKey) {
            _ = try SocialEnvelopeCipher(base64EncodedSessionKey: Data(repeating: 0, count: 16).base64EncodedString())
        }
        #expect(throws: SocialEnvelopeCipherError.invalidKey) {
            _ = try SocialEnvelopeCipher(base64EncodedSessionKey: "not-a-key")
        }
    }

    // MARK: - v2 associated data (session + topic binding)

    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private let topic = String(repeating: "a", count: 64)

    private func boundCipher(
        key: SymmetricKey,
        sessionID: UUID? = nil,
        topic: String? = nil
    ) -> SocialEnvelopeCipher {
        SocialEnvelopeCipher(
            sessionKey: key,
            sessionID: sessionID ?? self.sessionID,
            relayTopic: topic ?? self.topic
        )
    }

    @Test("A bound cipher emits the v2 prefix and round-trips")
    func boundCipherEmitsVersion2() throws {
        let key = SymmetricKey(size: .bits256)
        let cipher = boundCipher(key: key)
        let envelope = makeEnvelope()

        let sealed = try cipher.seal(envelope)

        #expect(sealed.hasPrefix(SocialEnvelopeCipher.version2Prefix))
        #expect(try cipher.open(sealed) == envelope)
    }

    /// Back-compat: sessions minted by an earlier build carry the session key, not the format, and
    /// there is no re-key path — so a v1 payload must still open under a v2-capable cipher.
    @Test("A v2-capable cipher still opens an unprefixed v1 payload")
    func version2CipherOpensLegacyPayload() throws {
        let key = SymmetricKey(size: .bits256)
        let legacySender = SocialEnvelopeCipher(sessionKey: key)   // unbound ⇒ seals v1
        let boundReceiver = boundCipher(key: key)
        let envelope = makeEnvelope()

        let legacySealed = try legacySender.seal(envelope)

        #expect(!legacySealed.hasPrefix(SocialEnvelopeCipher.version2Prefix))
        #expect(try boundReceiver.open(legacySealed) == envelope)
    }

    /// The point of the AAD: the same key is not enough. A payload sealed for one session must fail
    /// the *tag* when replayed into another, not merely be caught by the coordinator's guard.
    @Test("A v2 payload sealed for one session will not open bound to a different session")
    func version2PayloadIsBoundToItsSession() throws {
        let key = SymmetricKey(size: .bits256)
        let sender = boundCipher(key: key)
        let otherSession = boundCipher(key: key, sessionID: UUID())

        let sealed = try sender.seal(makeEnvelope())

        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try otherSession.open(sealed)
        }
    }

    @Test("A v2 payload sealed for one topic will not open bound to a different topic")
    func version2PayloadIsBoundToItsTopic() throws {
        let key = SymmetricKey(size: .bits256)
        let sender = boundCipher(key: key)
        let otherTopic = boundCipher(key: key, topic: String(repeating: "b", count: 64))

        let sealed = try sender.seal(makeEnvelope())

        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try otherTopic.open(sealed)
        }
    }

    /// Stripping the version prefix must not downgrade a v2 payload into an unauthenticated v1 open —
    /// the AAD is covered by the GCM tag, so the box simply fails to authenticate.
    @Test("Stripping the v2 prefix does not downgrade the payload")
    func strippingVersionPrefixFailsClosed() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try boundCipher(key: key).seal(makeEnvelope())
        let stripped = String(sealed.dropFirst(SocialEnvelopeCipher.version2Prefix.count))

        // Opened as v1 by an unbound cipher holding the same key: the tag covers the AAD, so it fails.
        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try SocialEnvelopeCipher(sessionKey: key).open(stripped)
        }
        // And by a bound cipher, which now treats it as v1 for lack of the prefix.
        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try boundCipher(key: key).open(stripped)
        }
    }

    /// An unbound cipher has no AAD to check a v2 payload against, so it refuses rather than
    /// bottoming out in a confusing generic failure.
    @Test("An unbound cipher refuses a v2 payload")
    func unboundCipherRefusesVersion2() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try boundCipher(key: key).seal(makeEnvelope())

        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try SocialEnvelopeCipher(sessionKey: key).open(sealed)
        }
    }

    /// The session/topic fields are length-delimited, so a crafted topic cannot shift bytes across the
    /// boundary to forge the same associated data as a different (session, topic) pair.
    @Test("Associated data is unambiguous across the session/topic boundary")
    func associatedDataIsUnambiguous() throws {
        let key = SymmetricKey(size: .bits256)
        let session = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        let sender = SocialEnvelopeCipher(sessionKey: key, sessionID: session, relayTopic: "abc")
        // Same concatenated bytes if the delimiter were absent.
        let confusable = SocialEnvelopeCipher(
            sessionKey: key,
            sessionID: session,
            relayTopic: "\u{0}abc"
        )

        let sealed = try sender.seal(makeEnvelope())

        #expect(throws: SocialEnvelopeCipherError.malformedPayload) {
            _ = try confusable.open(sealed)
        }
    }
}
