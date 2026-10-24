import CryptoKit
import Foundation
import SocialCore

/// Session-key material for a Social v1 shared session.
///
/// A shared session's symmetric key never touches the relay: it travels only inside the ``SocialInvite``
/// (delivered out-of-band via QR/share sheet), so relay payloads stay opaque. This namespace mints and
/// parses that key as a base64 string — the exact shape ``SocialInvite/encryptedSessionKey`` carries.
enum SocialSessionKey {
    /// Bit size of the AES-GCM session key. 256-bit is the CryptoKit default for `SymmetricKey(size:)`.
    static let bitCount = 256

    /// A fresh, cryptographically-random session key, base64-encoded for an invite payload.
    static func generateBase64Encoded() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    /// Parses a base64 session key back into a `SymmetricKey`, failing closed on malformed or
    /// wrong-length material rather than proceeding with a weak/partial key.
    static func symmetricKey(base64Encoded value: String) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: value), data.count == bitCount / 8 else {
            throw SocialEnvelopeCipherError.invalidKey
        }
        return SymmetricKey(data: data)
    }
}

enum SocialEnvelopeCipherError: Error, Equatable, Sendable {
    /// The base64 session-key material was missing, mis-encoded, or the wrong length.
    case invalidKey
    /// The payload was not valid base64, not a well-formed AES-GCM box, failed authentication
    /// (tampered or wrong key), or did not decode to a `SocialEventEnvelope`.
    case malformedPayload
}

/// Production ``SocialEnvelopeCiphering`` for Social v1: authenticated AES-GCM encryption of social
/// event envelopes under a per-session symmetric key.
///
/// The cipher is bound to *one* session key — matching the relay coordinator's `open(_:)`/`seal(_:)`
/// contract, which carries no topic/session discriminator — so one cipher (and one coordinator) serves
/// one shared session. `seal` JSON-encodes the envelope, AES-GCM-seals it, and base64-encodes the
/// combined box; `open` reverses that and fails closed (throwing ``SocialEnvelopeCipherError/malformedPayload``)
/// on any base64, framing, authentication, or decoding failure, so a corrupt, truncated, wrong-key, or
/// tampered payload is rejected rather than silently mis-handled.
///
/// ## Wire versioning and associated data
///
/// `seal` emits the **v2** format: the ASCII prefix `"A2."` followed by base64 of an AES-GCM box sealed
/// with associated data binding the payload to its session id *and* relay topic. `open` accepts both v2
/// and the unprefixed **v1** format (no associated data), so sessions minted by an earlier build keep
/// working — the invite carries the session key, not the format, and there is no re-key path.
///
/// Accepting v1 is not a downgrade hole. A v2 box cannot be stripped to v1 and still open: the AAD is
/// covered by the GCM tag, so opening it without the AAD fails authentication. And forging *any* box in
/// either format requires the session key, which only a member holds. So v1 acceptance leaves the
/// pre-existing property intact ("authenticated ⇒ key holder") while v2 additionally makes
/// cross-session and cross-topic reuse fail at the *tag* rather than only at
/// `SocialRelayCoordinator`'s `envelope.sessionID == boundSessionID` guard and `appendInbound`'s
/// id-dedupe. Those app-layer checks remain the defence for v1 traffic and stay in place for v2.
struct SocialEnvelopeCipher: SocialEnvelopeCiphering {
    /// Marks a payload whose GCM tag covers ``associatedData``. Chosen to be outside the base64
    /// alphabet (`.` is not a base64 character) so a v1 payload can never be mistaken for a v2 one.
    static let version2Prefix = "A2."

    private let key: SymmetricKey
    /// The session and topic this cipher's payloads are bound to, or `nil` for a cipher built without
    /// them (tests, and any caller that only needs v1 compatibility).
    private let associatedData: Data?

    // Seal and open are the only users of these coders, so they need only be self-consistent. Both use
    // the default (`.deferredToDate`) date strategy, which encodes `Date` losslessly as a `Double` — an
    // ISO-8601 strategy would truncate sub-second precision and break exact envelope round-tripping.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    init(sessionKey: SymmetricKey, sessionID: UUID? = nil, relayTopic: String? = nil) {
        self.key = sessionKey
        self.associatedData = Self.associatedData(sessionID: sessionID, relayTopic: relayTopic)
    }

    /// Builds a cipher from an invite's base64 session-key material. Throws
    /// ``SocialEnvelopeCipherError/invalidKey`` when the material is malformed.
    ///
    /// Pass `sessionID`/`relayTopic` to emit v2 payloads bound to them. Omitting both yields a cipher
    /// that seals v1 — still authenticated, just not bound.
    init(base64EncodedSessionKey value: String, sessionID: UUID? = nil, relayTopic: String? = nil) throws {
        self.key = try SocialSessionKey.symmetricKey(base64Encoded: value)
        self.associatedData = Self.associatedData(sessionID: sessionID, relayTopic: relayTopic)
    }

    /// The bytes the GCM tag additionally covers: session id and relay topic.
    ///
    /// The framing is NUL-**delimited**, not length-prefixed (an earlier version of this comment said
    /// otherwise). It is still unambiguous, for two independent reasons, and the reasoning is written
    /// out because it is what rules out a crafted topic shifting the field boundary: the session id is
    /// always exactly 36 characters of lowercased UUID and cannot itself contain a NUL, so the single
    /// separator byte always falls in the same place; and the relay topic is the final field with no
    /// terminator, so nothing follows it to be confused with.
    private static func associatedData(sessionID: UUID?, relayTopic: String?) -> Data? {
        guard let sessionID, let relayTopic else { return nil }
        var data = Data("auralis.social.envelope.v2\u{0}".utf8)
        data.append(Data(sessionID.uuidString.lowercased().utf8))
        data.append(0)
        data.append(Data(relayTopic.utf8))
        return data
    }

    func seal(_ envelope: SocialEventEnvelope) throws -> String {
        let plaintext = try Self.encoder.encode(envelope)
        let sealedBox: AES.GCM.SealedBox
        if let associatedData {
            sealedBox = try AES.GCM.seal(plaintext, using: key, authenticating: associatedData)
        } else {
            sealedBox = try AES.GCM.seal(plaintext, using: key)
        }
        guard let combined = sealedBox.combined else {
            // Only occurs for a non-standard nonce size, which we never use.
            throw SocialEnvelopeCipherError.malformedPayload
        }
        let encoded = combined.base64EncodedString()
        return associatedData == nil ? encoded : Self.version2Prefix + encoded
    }

    func open(_ message: String) throws -> SocialEventEnvelope {
        // The prefix selects the format; it is not attacker-chosen in any useful way, because a v2 box
        // cannot open without its AAD and a v1 box cannot open with one.
        let isVersion2 = message.hasPrefix(Self.version2Prefix)
        let body = isVersion2 ? String(message.dropFirst(Self.version2Prefix.count)) : message

        guard let combined = Data(base64Encoded: body) else {
            throw SocialEnvelopeCipherError.malformedPayload
        }
        // A v2 payload requires a bound cipher: without the AAD there is nothing to authenticate it
        // against, and opening it as v1 would fail the tag anyway. Refuse explicitly rather than
        // bottoming out in a generic failure.
        if isVersion2, associatedData == nil {
            throw SocialEnvelopeCipherError.malformedPayload
        }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let plaintext: Data
            if isVersion2, let associatedData {
                plaintext = try AES.GCM.open(sealedBox, using: key, authenticating: associatedData)
            } else {
                plaintext = try AES.GCM.open(sealedBox, using: key)
            }
            return try Self.decoder.decode(SocialEventEnvelope.self, from: plaintext)
        } catch {
            // Fail closed: bad framing, authentication failure (tampered/wrong key), or a payload that
            // does not decode to an envelope are all indistinguishable to a caller and equally rejected.
            throw SocialEnvelopeCipherError.malformedPayload
        }
    }
}
