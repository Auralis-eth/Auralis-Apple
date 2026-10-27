@testable import Auralis
import Foundation
import AuralisOperators
import Testing
import WalletAdapters

@Suite("Social wallet join verifier")
struct SocialWalletJoinVerifierTests {
    @Test("verified wallet ownership produces a participant proof")
    func verifiedWalletOwnershipProducesProof() async throws {
        let verifier = RecordingWalletOwnershipVerifier(result: true)
        let service = SocialWalletJoinVerifier(walletVerifier: verifier)
        let invite = makeInvite()
        var validator = SocialJoinChallengeValidator()

        let proof = try await service.verifyJoin(
            invite: invite,
            caip10Account: "eip155:1:0xabc",
            sessionID: "wallet-session",
            verificationMethod: "0xsig",
            now: Date(timeIntervalSince1970: 10),
            validator: &validator
        )

        let call = try #require(await verifier.calls().first)
        #expect(call.address == "0xabc")
        #expect(call.chain == .ethereum)
        #expect(call.statement == proof.challenge.signingMessage)
        #expect(proof.verificationMethod == "0xsig")
    }

    @Test("rejected wallet ownership fails closed")
    func rejectedWalletOwnershipFailsClosed() async {
        let service = SocialWalletJoinVerifier(walletVerifier: RecordingWalletOwnershipVerifier(result: false))
        var validator = SocialJoinChallengeValidator()

        await #expect(throws: SocialJoinChallengeError.signatureRejected) {
            try await service.verifyJoin(
                invite: makeInvite(),
                caip10Account: "eip155:1:0xabc",
                sessionID: "wallet-session",
                now: Date(timeIntervalSince1970: 10),
                validator: &validator
            )
        }
    }

    @Test("unsupported CAIP-10 account fails before wallet request")
    func unsupportedCAIP10FailsBeforeWalletRequest() async {
        let verifier = RecordingWalletOwnershipVerifier(result: true)
        let service = SocialWalletJoinVerifier(walletVerifier: verifier)
        var validator = SocialJoinChallengeValidator()

        await #expect(throws: SocialWalletJoinVerifierError.unsupportedCAIP10("cosmos:cosmoshub-4:addr")) {
            try await service.verifyJoin(
                invite: makeInvite(),
                caip10Account: "cosmos:cosmoshub-4:addr",
                sessionID: "wallet-session",
                now: Date(timeIntervalSince1970: 10),
                validator: &validator
            )
        }
        #expect(await verifier.calls().isEmpty)
    }

    /// The wallet must never be asked to sign a challenge that does not serialize unambiguously.
    ///
    /// `SocialJoinChallenge.hasCanonicalFields` documents this as the caller's obligation, and the
    /// validator enforcing it afterwards is too late: a crafted invite whose `relayTopic` carries a
    /// line break makes two structurally different challenges produce the same `signingMessage`, so
    /// the signature collected here is also valid for a challenge the signer never saw. The refusal
    /// protected the local bookkeeping while the EIP-191 response had already been produced — and it
    /// travels over a relay this codebase treats as untrusted. Asserting `calls().isEmpty` is the
    /// whole point of the test; the thrown error alone would pass against the pre-fix code.
    @Test(arguments: ["relayTopic", "nonce"])
    func aChallengeThatCannotSerializeUnambiguouslyNeverReachesTheWallet(field: String) async {
        let forged = "t1\naccount:eip155:1:0xVICTIM\nnonce:n1\nexpires:x\nx:"
        let invite = SocialInvite(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            relayTopic: field == "relayTopic" ? forged : "topic-a",
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: Date(timeIntervalSince1970: 100),
            nonce: field == "nonce" ? forged : "nonce"
        )
        let verifier = RecordingWalletOwnershipVerifier(result: true)
        let service = SocialWalletJoinVerifier(walletVerifier: verifier)
        var validator = SocialJoinChallengeValidator()

        await #expect(throws: SocialJoinChallengeError.malformedChallengeField) {
            try await service.verifyJoin(
                invite: invite,
                caip10Account: "eip155:1:0xabc",
                sessionID: "wallet-session",
                now: Date(timeIntervalSince1970: 10),
                validator: &validator
            )
        }
        #expect(await verifier.calls().isEmpty)
    }

    /// Line-break screening is not enough on its own.
    ///
    /// Screening only for newlines still let a hostile QR put up to 160 arbitrary non-newline
    /// characters into the `topic:` and `nonce:` lines of the message the victim's wallet signs.
    /// Nothing a real mint produces looks like that, so the fields are now positively validated
    /// against the mint's exact shape — lowercase hex of the minted length — rather than merely
    /// screened for the one character that breaks serialization.
    @Test("a topic or nonce the mint could not have produced never reaches the wallet", arguments: [
        "wss://attacker.example/pwned",                                 // not hex at all
        "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789", // uppercase
        "abc",                                                          // too short
        "",                                                             // empty
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" // too long
    ])
    func aFieldTheMintCouldNotProduceNeverReachesTheWallet(forged: String) async {
        let invite = SocialInvite(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            relayTopic: forged,
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: Date(timeIntervalSince1970: 100),
            nonce: String(repeating: "b", count: SocialInviteMint.nonceByteCount * 2)
        )
        let verifier = RecordingWalletOwnershipVerifier(result: true)
        let service = SocialWalletJoinVerifier(walletVerifier: verifier)
        var validator = SocialJoinChallengeValidator()

        await #expect(throws: SocialJoinChallengeError.malformedChallengeField) {
            try await service.verifyJoin(
                invite: invite,
                caip10Account: "eip155:1:0xabc",
                sessionID: "wallet-session",
                now: Date(timeIntervalSince1970: 10),
                validator: &validator
            )
        }
        #expect(await verifier.calls().isEmpty)
    }

    /// A genuinely minted invite must still pass — the validation is a shape check, not a blanket
    /// refusal, and over-tightening it would make every real join fail closed.
    @Test("a freshly minted invite passes the shape check and reaches the wallet")
    func aMintedInviteReachesTheWallet() async throws {
        let invite = SocialInviteMint.mint(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            inviterParticipantID: "alice",
            now: Date(timeIntervalSince1970: 10)
        )
        let verifier = RecordingWalletOwnershipVerifier(result: true)
        let service = SocialWalletJoinVerifier(walletVerifier: verifier)
        var validator = SocialJoinChallengeValidator()

        _ = try await service.verifyJoin(
            invite: invite,
            caip10Account: "eip155:1:0xabc",
            sessionID: "wallet-session",
            verificationMethod: "0xsig",
            now: Date(timeIntervalSince1970: 20),
            validator: &validator
        )

        #expect(await verifier.calls().count == 1)
    }

    /// The account is the caller's string rather than the invite's, so it is the third way a line
    /// break reaches `signingMessage`.
    @Test
    func anAccountCarryingALineBreakNeverReachesTheWallet() async {
        let verifier = RecordingWalletOwnershipVerifier(result: true)
        let service = SocialWalletJoinVerifier(walletVerifier: verifier)
        var validator = SocialJoinChallengeValidator()

        await #expect(throws: SocialJoinChallengeError.malformedChallengeField) {
            try await service.verifyJoin(
                invite: makeInvite(),
                caip10Account: "eip155:1:0xabc\nnonce:forged",
                sessionID: "wallet-session",
                now: Date(timeIntervalSince1970: 10),
                validator: &validator
            )
        }
        #expect(await verifier.calls().isEmpty)
    }

    /// Mint-shaped `relayTopic` and `nonce`, not placeholders.
    ///
    /// The verifier now requires both to be exactly the lowercase hex `SocialInviteMint` emits before
    /// it will ask the wallet to EIP-191-sign them — otherwise a hostile QR could put ~160 arbitrary
    /// characters into the `topic:`/`nonce:` lines of the signing message. `"topic-a"`/`"nonce"` are
    /// values no mint can produce, so a fixture using them was testing a shape that cannot occur.
    private func makeInvite() -> SocialInvite {
        SocialInvite(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            relayTopic: String(repeating: "a", count: SocialInviteMint.topicByteCount * 2),
            encryptedSessionKey: "ciphertext",
            inviterParticipantID: "alice",
            expiresAt: Date(timeIntervalSince1970: 100),
            nonce: String(repeating: "b", count: SocialInviteMint.nonceByteCount * 2)
        )
    }
}

private actor RecordingWalletOwnershipVerifier: SocialWalletOwnershipVerifying {
    struct Call: Equatable, Sendable {
        let address: String
        let chain: WalletChain
        let sessionID: WalletSessionID
        let statement: String
        let expiryDate: Date
    }

    private let result: Bool
    private var recordedCalls: [Call] = []

    init(result: Bool) {
        self.result = result
    }

    func verifyOwnership(
        of address: String,
        chain: WalletChain,
        in sessionId: WalletSessionID,
        statement: String,
        expiryDate: Date
    ) async throws -> Bool {
        recordedCalls.append(Call(
            address: address,
            chain: chain,
            sessionID: sessionId,
            statement: statement,
            expiryDate: expiryDate
        ))
        return result
    }

    func calls() -> [Call] { recordedCalls }
}
