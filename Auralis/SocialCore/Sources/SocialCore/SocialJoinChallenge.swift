import Foundation

public struct SocialJoinChallenge: Equatable, Sendable, Codable {
    public let sessionID: UUID
    public let relayTopic: String
    public let caip10Account: String
    public let nonce: String
    public let expiresAt: Date

    /// Routed through the memberwise initializer so there is a single clamp site. The invite's own
    /// fields are already bounded; `caip10Account` is the caller's string and is not.
    public init(invite: SocialInvite, caip10Account: String) {
        self.init(
            sessionID: invite.sessionID,
            relayTopic: invite.relayTopic,
            caip10Account: caip10Account,
            nonce: invite.nonce,
            expiresAt: invite.expiresAt
        )
    }

    public init(
        sessionID: UUID,
        relayTopic: String,
        caip10Account: String,
        nonce: String,
        expiresAt: Date
    ) {
        self.sessionID = sessionID
        // Clamped at the *same* limit as the corresponding ``SocialInvite`` fields, and that
        // symmetry is the whole point rather than a size precaution.
        //
        // `acceptVerifiedSignature` compares this type against the invite field by field —
        // `challenge.relayTopic == invite.relayTopic`, `challenge.nonce == invite.nonce` — and the
        // invite clamps all three. Bounding one side of an equality comparison and not the other is
        // how a value comes to be stored as two different strings; here an over-long topic or nonce
        // would make a legitimate challenge fail against its own invite, reported as the actively
        // misleading `.wrongRelayTopic` or `.replayedNonce`. It also reaches further than the
        // comparison: `relayTopic` and `nonce` are interpolated into ``signingMessage``, which is
        // what the wallet actually signs, so the two sides disagreeing means signing a message that
        // does not describe the invite being joined.
        //
        // `caip10Account` takes the same limit as ``SocialParticipantIdentity/caip10Account`` for
        // the same reason — it becomes that field on the identity minted from this proof.
        //
        // No real value approaches 160: a relay topic is 64 hex characters, a nonce 32, and a
        // CAIP-10 account tops out near 115. Nothing legitimate is truncated; the limit exists so
        // the two types agree.
        self.relayTopic = String(relayTopic.prefix(SocialParticipantIdentity.identifierLimit))
        self.caip10Account = String(caip10Account.prefix(SocialParticipantIdentity.identifierLimit))
        self.nonce = String(nonce.prefix(SocialParticipantIdentity.identifierLimit))
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, relayTopic, caip10Account, nonce, expiresAt
    }

    /// Decodes through the memberwise initializer so its clamps run on the decode path too.
    ///
    /// ``SocialParticipantProof`` carries a challenge and is `Codable`, and transporting that proof
    /// is the documented way the relay restriction gets lifted — so this type is on track to become
    /// wire data, at which point synthesized `Codable` would bypass the bounds above on exactly the
    /// path that matters. Closing it now costs nothing and means the clamp cannot be forgotten when
    /// the proof starts travelling.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            relayTopic: try container.decode(String.self, forKey: .relayTopic),
            caip10Account: try container.decode(String.self, forKey: .caip10Account),
            nonce: try container.decode(String.self, forKey: .nonce),
            expiresAt: try container.decode(Date.self, forKey: .expiresAt)
        )
    }

    /// Whether this challenge serializes to an unambiguous ``signingMessage``.
    ///
    /// ``signingMessage`` is a newline-delimited `key:value` block, so a value containing a line
    /// break can forge a field: a crafted invite with
    /// `relayTopic = "t1\naccount:eip155:1:0xVICTIM\nnonce:n1\nexpires:…\nx:"` makes two structurally
    /// different challenges serialize to the same string, and one collected signature becomes valid
    /// for a challenge the signer never saw. Colons cannot be rejected — they are structural in both
    /// CAIP-10 accounts and relay topics — but a value free of line breaks cannot open a new field,
    /// and each key prefix is a fixed literal, so rejecting line breaks closes the ambiguity.
    ///
    /// Callers must check this *before* asking a wallet to sign; ``SocialJoinChallengeValidator``
    /// enforces it again at the point a proof would be issued.
    public var hasCanonicalFields: Bool {
        [relayTopic, caip10Account, nonce].allSatisfy { field in
            field.rangeOfCharacter(from: .newlines) == nil
        }
    }

    public var signingMessage: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return """
        Auralis shared session join
        session:\(sessionID.uuidString)
        topic:\(relayTopic)
        account:\(caip10Account)
        nonce:\(nonce)
        expires:\(formatter.string(from: expiresAt))
        """
    }
}

public struct SocialParticipantProof: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let challenge: SocialJoinChallenge
    /// How ownership was established — **not** the signature itself, and deliberately not named as
    /// though it were.
    ///
    /// This field used to be `signature: String`, which overstated what it holds. The ownership check
    /// runs through `WalletConnector.verifyOwnership`, whose result is a `Bool`: the EIP-191 signature
    /// is produced and validated inside the connector and never handed back, so the production caller
    /// passes the constant `"wallet-verified"`. A field called `signature` carrying a fixed string is
    /// not evidence, and nothing in the app has ever read it — it was written and never consulted.
    ///
    /// Renamed before the type starts travelling rather than after, which is the whole point. The
    /// doc on ``SocialJoinChallenge``'s decoder records that transporting this proof is the documented
    /// way to lift the relay's local-verification restriction; on that day a remote peer would be
    /// reading this field, and `signature` is precisely the name that would invite it to be trusted as
    /// cryptographic proof of ownership. It is not: it attests only that *this device's* connector
    /// answered yes. Transporting a proof that a peer can independently verify requires carrying the
    /// real signature **and** verifying it against ``SocialJoinChallenge/signingMessage`` on arrival —
    /// which is a change to this type, not a change of value in this field.
    public let verificationMethod: String
    public let verifiedAt: Date

    /// ``verificationMethod`` for the only method that exists today: the wallet connector answered
    /// `true` to an ownership challenge on this device. Declared once here so the two call sites
    /// cannot drift to different spellings of the same fact.
    public static let connectorVerified = "wallet-verified"

    public init(
        id: String,
        challenge: SocialJoinChallenge,
        verificationMethod: String,
        verifiedAt: Date = .now
    ) {
        self.id = id
        self.challenge = challenge
        self.verificationMethod = verificationMethod
        self.verifiedAt = verifiedAt
    }
}

public enum SocialJoinChallengeError: Error, Equatable, Sendable {
    case expiredInvite
    case wrongSession
    case wrongRelayTopic
    case wrongAccount
    case replayedNonce
    case signatureRejected
    /// A field carried a line break, making ``SocialJoinChallenge/signingMessage`` ambiguous.
    case malformedChallengeField
}

public struct SocialJoinChallengeValidator: Equatable, Sendable, Codable {
    /// Consumed join nonces, keyed by ``consumptionKey(sessionID:nonce:)`` rather than by the bare
    /// nonce. A nonce is only meaningful within the session that issued it, so keying globally meant
    /// an unrelated session reusing the same nonce string — or anyone who had merely *seen* a QR code
    /// and burned its nonce first — could block a legitimate join with a misleading `.replayedNonce`.
    public private(set) var consumedNonces: Set<String>

    public init(consumedNonces: Set<String> = []) {
        self.consumedNonces = consumedNonces
    }

    public static func consumptionKey(sessionID: UUID, nonce: String) -> String {
        "\(sessionID.uuidString):\(nonce)"
    }

    /// - Parameters:
    ///   - verificationMethod: How ownership was established, recorded on the proof. Not a signature
    ///     — see ``SocialParticipantProof/verificationMethod``.
    ///   - signatureVerified: The actual trust decision, from the wallet connector. This is the only
    ///     argument that gates the proof.
    public mutating func acceptVerifiedSignature(
        invite: SocialInvite,
        challenge: SocialJoinChallenge,
        verificationMethod: String,
        signatureVerified: Bool,
        now: Date = .now
    ) throws -> SocialParticipantProof {
        // Checked first: a non-canonical challenge has no single meaning to verify a signature
        // against, so nothing downstream should run on it.
        guard challenge.hasCanonicalFields,
              invite.relayTopic.rangeOfCharacter(from: .newlines) == nil,
              invite.nonce.rangeOfCharacter(from: .newlines) == nil else {
            throw SocialJoinChallengeError.malformedChallengeField
        }
        guard !invite.isExpired(now: now), challenge.expiresAt > now else {
            throw SocialJoinChallengeError.expiredInvite
        }
        guard challenge.sessionID == invite.sessionID else {
            throw SocialJoinChallengeError.wrongSession
        }
        guard challenge.relayTopic == invite.relayTopic else {
            throw SocialJoinChallengeError.wrongRelayTopic
        }
        let consumptionKey = Self.consumptionKey(sessionID: challenge.sessionID, nonce: challenge.nonce)
        guard challenge.nonce == invite.nonce, !consumedNonces.contains(consumptionKey) else {
            throw SocialJoinChallengeError.replayedNonce
        }
        guard !challenge.caip10Account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SocialJoinChallengeError.wrongAccount
        }
        guard signatureVerified else {
            throw SocialJoinChallengeError.signatureRejected
        }

        consumedNonces.insert(consumptionKey)
        return SocialParticipantProof(
            id: "\(challenge.sessionID.uuidString):\(challenge.caip10Account):\(challenge.nonce)",
            challenge: challenge,
            verificationMethod: verificationMethod,
            verifiedAt: now
        )
    }
}
