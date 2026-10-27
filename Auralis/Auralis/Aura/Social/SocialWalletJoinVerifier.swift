import Foundation
import AuralisOperators
import WalletAdapters

protocol SocialWalletOwnershipVerifying: Sendable {
    func verifyOwnership(
        of address: String,
        chain: WalletChain,
        in sessionId: WalletSessionID,
        statement: String,
        expiryDate: Date
    ) async throws -> Bool
}

struct WalletConnectorSocialOwnershipVerifier: SocialWalletOwnershipVerifying {
    private let connector: any WalletConnector

    init(connector: any WalletConnector) {
        self.connector = connector
    }

    func verifyOwnership(
        of address: String,
        chain: WalletChain,
        in sessionId: WalletSessionID,
        statement: String,
        expiryDate: Date
    ) async throws -> Bool {
        try await connector.verifyOwnership(
            of: address,
            chain: chain,
            in: sessionId,
            statement: statement,
            expiryDate: expiryDate
        )
    }
}

enum SocialWalletJoinVerifierError: Error, Equatable, Sendable {
    case unsupportedCAIP10(String)
    case missingAddress(String)
}

struct SocialWalletJoinVerifier: Sendable {
    private let walletVerifier: any SocialWalletOwnershipVerifying

    init(walletVerifier: any SocialWalletOwnershipVerifying) {
        self.walletVerifier = walletVerifier
    }

    func verifyJoin(
        invite: SocialInvite,
        caip10Account: String,
        sessionID: WalletSessionID,
        verificationMethod: String = SocialParticipantProof.connectorVerified,
        now: Date = .now,
        validator: inout SocialJoinChallengeValidator
    ) async throws -> SocialParticipantProof {
        let challenge = SocialJoinChallenge(invite: invite, caip10Account: caip10Account)
        // Checked *before* the wallet is asked to sign, which is what
        // ``SocialJoinChallenge/hasCanonicalFields`` documents as the caller's obligation. The
        // validator enforces it again below, but by then the damage is done: a crafted invite whose
        // `relayTopic` carries a line break makes two structurally different challenges serialize to
        // the same ``signingMessage``, so the signature the wallet produces here is also valid for a
        // challenge the signer never saw. Refusing afterwards protects the local bookkeeping and not
        // the user's wallet — the EIP-191 response has already been produced, and it travels over a
        // relay this codebase treats as untrusted.
        //
        // The invite's own fields are checked alongside the challenge's for the reason given on
        // `acceptVerifiedSignature`: the challenge clamps to 160 characters and the invite does not,
        // so a break living past the clamp is invisible on the challenge side.
        // Positively validated against the shape a *minted* invite actually has, rather than merely
        // screened for line breaks. A hostile QR could otherwise put up to 160 arbitrary non-newline
        // characters into each of the `topic:` and `nonce:` lines of `signingMessage` and have the
        // victim's wallet EIP-191-sign them. The fixed preamble bounds cross-protocol reuse, but there
        // is no reason to sign anything that could not have come from `SocialInviteMint`.
        guard challenge.hasCanonicalFields,
              SocialInviteMint.isMintedHex(invite.relayTopic, byteCount: SocialInviteMint.topicByteCount),
              SocialInviteMint.isMintedHex(invite.nonce, byteCount: SocialInviteMint.nonceByteCount) else {
            throw SocialJoinChallengeError.malformedChallengeField
        }
        let account = try WalletJoinAccount(caip10Account)
        let verified = try await walletVerifier.verifyOwnership(
            of: account.address,
            chain: account.chain,
            in: sessionID,
            statement: challenge.signingMessage,
            expiryDate: challenge.expiresAt
        )
        return try validator.acceptVerifiedSignature(
            invite: invite,
            challenge: challenge,
            verificationMethod: verificationMethod,
            signatureVerified: verified,
            now: now
        )
    }

}

private struct WalletJoinAccount: Sendable {
    let chain: WalletChain
    let address: String

    init(_ caip10: String) throws {
        // Shared with `SocialCAIP10.isCAIP10` so the "is this a CAIP-10?" check and the parser that
        // consumes it cannot disagree about empty components.
        let parts = SocialCAIP10.split(caip10)
        guard parts.count == 3 else {
            throw SocialWalletJoinVerifierError.unsupportedCAIP10(caip10)
        }
        guard !parts[2].isEmpty else {
            throw SocialWalletJoinVerifierError.missingAddress(caip10)
        }
        self.chain = try Self.chain(namespace: parts[0], reference: parts[1], caip10: caip10)
        self.address = parts[2]
    }

    private static func chain(namespace: String, reference: String, caip10: String) throws -> WalletChain {
        switch (namespace, reference) {
        case ("eip155", "1"):
            return .ethereum
        case ("eip155", "137"):
            return .polygon
        case ("eip155", "8453"):
            return .base
        case ("eip155", "10"):
            return .optimism
        case ("eip155", "42161"):
            return .arbitrum
        case ("eip155", "43114"):
            return .avalanche
        case ("eip155", "56"):
            return .bnb
        case ("eip155", "324"):
            return .zksync
        case ("eip155", "59144"):
            return .linea
        case ("solana", _):
            return .solana
        default:
            throw SocialWalletJoinVerifierError.unsupportedCAIP10(caip10)
        }
    }
}
