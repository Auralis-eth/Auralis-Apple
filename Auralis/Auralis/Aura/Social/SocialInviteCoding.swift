import Foundation
import SocialCore

enum SocialInviteCodingError: Error, Equatable, Sendable {
    /// The string was not a well-formed, prefixed, base64 `SocialInvite` payload.
    case malformed
    /// It decoded to a `SocialInvite`, but one of its fields is outside anything ``SocialInviteMint``
    /// could have produced.
    case implausibleInvite
}

/// Encodes a ``SocialInvite`` to a compact, shareable string (and back) for QR codes, share sheets, and
/// paste-to-join. The payload is a scheme-prefixed base64 JSON blob — opaque to the relay (the invite
/// never travels over it) and self-describing enough to reject a random pasted string. `decode` fails
/// closed on anything that isn't a valid invite.
enum SocialInviteCoding {
    /// Prefix that marks a string as an Auralis invite, so paste-to-join can reject unrelated text.
    static let scheme = "aura-social"

    static func encode(_ invite: SocialInvite) throws -> String {
        let data = try JSONEncoder().encode(invite)
        return scheme + ":" + data.base64EncodedString()
    }

    static func decode(_ string: String, now: Date = .now) throws -> SocialInvite {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = scheme + ":"
        guard trimmed.hasPrefix(prefix) else { throw SocialInviteCodingError.malformed }
        let base64 = String(trimmed.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: base64) else { throw SocialInviteCodingError.malformed }
        let invite: SocialInvite
        do {
            invite = try JSONDecoder().decode(SocialInvite.self, from: data)
        } catch {
            throw SocialInviteCodingError.malformed
        }
        try validate(invite, now: now)
        return invite
    }

    /// Screens a decoded invite against the shape ``SocialInviteMint`` actually mints.
    ///
    /// Decoding used to assert nothing beyond "it is a `SocialInvite`", and the join path only checked
    /// `!invite.isExpired()`. So a hand-crafted QR carrying `expiresAt` in the year 3000 was accepted
    /// verbatim and saved: the invite would never be reclaimed by expiry pruning, and the session's
    /// durable log was bounded only by the per-session envelope ceiling. The topic/nonce shape is
    /// screened here too — it was previously enforced only on the optional P3 signing path, so an
    /// invite with arbitrary field contents could be persisted and subscribed as long as its owner
    /// never ran a wallet challenge.
    private static func validate(_ invite: SocialInvite, now: Date) throws {
        guard SocialInviteMint.isMintedHex(invite.relayTopic, byteCount: SocialInviteMint.topicByteCount),
              SocialInviteMint.isMintedHex(invite.nonce, byteCount: SocialInviteMint.nonceByteCount),
              invite.expiresAt <= SocialInviteMint.latestPlausibleExpiry(now: now) else {
            throw SocialInviteCodingError.implausibleInvite
        }
    }
}
