import Foundation
import AuralisOperators

/// Mints a ``SocialInvite`` for a shared session (Social v1).
///
/// An invite is the out-of-band join token (shared via QR/share sheet, never via the relay). It carries
/// a fresh relay topic, a fresh symmetric session key, a single-use nonce, and an expiry. The topic and
/// nonce are random hex and deliberately carry no wallet address, title, or other user-readable metadata,
/// so a relay that only ever sees the topic learns nothing about the session (per the relay-readiness
/// privacy requirement). The session key travels *inside* the invite, so relay payloads stay opaque.
enum SocialInviteMint {
    /// Invites live for a week by default — long enough to hand out, short enough to bound replay risk.
    static let defaultTTL: TimeInterval = 7 * 24 * 60 * 60
    /// 32 random bytes → a 256-bit relay topic (64 hex chars).
    static let topicByteCount = 32
    /// 16 random bytes → a 128-bit single-use join nonce (32 hex chars).
    static let nonceByteCount = 16

    /// `ttl` is clamped to ``defaultTTL``, so a minted invite can never exceed what a joiner will
    /// accept. Without the clamp the ceiling in ``latestPlausibleExpiry(now:)`` and this
    /// caller-supplied TTL were free to drift apart, and a host passing a longer TTL would mint
    /// invites that every joiner rejected as `implausibleInvite` — a host-side bug surfacing only as
    /// "that invite code isn't valid" on someone else's device.
    static func mint(
        sessionID: UUID,
        inviterParticipantID: String,
        now: Date = .now,
        ttl: TimeInterval = defaultTTL
    ) -> SocialInvite {
        SocialInvite(
            sessionID: sessionID,
            relayTopic: randomHex(byteCount: topicByteCount),
            encryptedSessionKey: SocialSessionKey.generateBase64Encoded(),
            inviterParticipantID: inviterParticipantID,
            expiresAt: now.addingTimeInterval(min(max(1, ttl), defaultTTL)),
            nonce: randomHex(byteCount: nonceByteCount)
        )
    }

    /// Whether `value` is exactly the lowercase hex ``randomHex(byteCount:)`` emits.
    ///
    /// Lives here, next to the minter, so the "is this a minted field?" screen cannot drift from what
    /// minting actually produces. Applied both when decoding an invite and before asking a wallet to
    /// sign a join challenge.
    static func isMintedHex(_ value: String, byteCount: Int) -> Bool {
        value.count == byteCount * 2 && value.allSatisfy { $0.isASCII && $0.isHexDigit && !$0.isUppercase }
    }

    /// The furthest-future expiry an invite may legitimately claim, with a day of slack for clock skew
    /// between the host and the joiner.
    static func latestPlausibleExpiry(now: Date = .now) -> Date {
        now.addingTimeInterval(defaultTTL + 24 * 60 * 60)
    }

    /// Cryptographically-random lowercase hex of `byteCount` bytes. `SystemRandomNumberGenerator` is
    /// documented as cryptographically secure on Apple platforms.
    static func randomHex(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        var hex = ""
        hex.reserveCapacity(byteCount * 2)
        for _ in 0..<byteCount {
            hex += String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator))
        }
        return hex
    }
}
