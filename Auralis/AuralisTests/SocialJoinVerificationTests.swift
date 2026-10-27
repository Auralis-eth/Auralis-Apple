@testable import Auralis
import Foundation
import AuralisOperators
import Testing
import WalletConnectorKit

@Suite("Social join verification (P3)")
struct SocialJoinVerificationServiceTests {
    private let account = "eip155:1:0x" + String(repeating: "a", count: 40)
    private let session = WalletSessionID(rawValue: "wallet-session")

    private func service(ownershipVerified: Bool, store: SocialEventLogStore) -> SocialJoinVerificationService {
        SocialJoinVerificationService(
            verifier: SocialWalletJoinVerifier(walletVerifier: FakeOwnershipVerifier(result: ownershipVerified)),
            eventLogStore: store
        )
    }

    @Test("Verified ownership yields a proof and records a verified participantJoined")
    func verifiedRecordsParticipant() async throws {
        let store = SocialEventLogStore()
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "host")

        let proof = try await service(ownershipVerified: true, store: store).verifyAndRecordJoin(
            invite: invite,
            caip10Account: account,
            displayName: "Alice",
            walletSessionID: session
        )

        #expect(proof.challenge.sessionID == invite.sessionID)
        let envelopes = await store.allEnvelopes()
        #expect(envelopes.count == 1)
        guard case let .participantJoined(identity) = envelopes.first?.event else {
            Issue.record("expected participantJoined, got \(String(describing: envelopes.first?.event))")
            return
        }
        #expect(identity.verificationState == .verified)
        #expect(identity.caip10Account == account)
        #expect(identity.proofID == proof.id)
        #expect(identity.canAuthorBindingEvents)
    }

    @Test("Rejected ownership throws and records nothing")
    func rejectedRecordsNothing() async {
        let store = SocialEventLogStore()
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "host")

        await #expect(throws: SocialJoinChallengeError.signatureRejected) {
            _ = try await service(ownershipVerified: false, store: store).verifyAndRecordJoin(
                invite: invite, caip10Account: account, displayName: "Alice", walletSessionID: session
            )
        }
        #expect(await store.allEnvelopes().isEmpty)
    }

    @MainActor
    @Test("SocialAssembly.makeJoinVerifier builds a working verifier from an ownership seam")
    func assemblyFactoryBuildsVerifier() async throws {
        let store = SocialEventLogStore()
        let verifier = SocialAssembly.makeJoinVerifier(
            ownershipVerifier: FakeOwnershipVerifier(result: true),
            eventLogStore: store
        )
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "host")

        _ = try await verifier.verifyAndRecordJoin(
            invite: invite, caip10Account: account, displayName: "Alice", walletSessionID: session
        )
        let recordedVerified = await store.allEnvelopes().contains { envelope in
            if case let .participantJoined(identity) = envelope.event { return identity.verificationState == .verified }
            return false
        }
        #expect(recordedVerified)
    }

    @Test("A replayed invite nonce is rejected on the second join")
    func replayRejected() async throws {
        let store = SocialEventLogStore()
        let service = service(ownershipVerified: true, store: store)
        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "host")

        _ = try await service.verifyAndRecordJoin(invite: invite, caip10Account: account, displayName: "Alice", walletSessionID: session)
        await #expect(throws: SocialJoinChallengeError.replayedNonce) {
            _ = try await service.verifyAndRecordJoin(invite: invite, caip10Account: account, displayName: "Alice", walletSessionID: session)
        }
        // Only the first, successful join was recorded.
        #expect(await store.allEnvelopes().count == 1)
    }
}

@MainActor
@Suite("Invite exchange model — P3 join verification")
struct SocialInviteExchangeVerificationTests {
    private let account = "eip155:1:0x" + String(repeating: "b", count: 40)

    @Test("Import with a verifier records a verified participant in the shared log")
    func importRecordsVerifiedParticipant() async throws {
        let store = SocialEventLogStore()
        let assembly = SocialRelayAssembly(
            composition: SocialRelayComposition(
                configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
                eventLogStore: store
            ),
            collaboratorsFactory: { _ in
                SocialRelayCollaborators(transport: NoopQueueTransport(), inboundSource: NoopInboundSource())
            }
        )
        let verifier = SocialJoinVerificationService(
            verifier: SocialWalletJoinVerifier(walletVerifier: FakeOwnershipVerifier(result: true)),
            eventLogStore: store
        )
        let model = SocialInviteExchangeModel(
            assembly: assembly,
            participantID: account,
            joinVerifier: verifier,
            walletSessionIDProvider: { WalletSessionID(rawValue: "s") }
        )

        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "host")
        await model.importInvite(code: try SocialInviteCoding.encode(invite))

        if case let .joined(_, notice) = model.state {
            #expect(notice == nil)
        } else {
            Issue.record("expected joined, got \(model.state)")
        }
        let recordedVerified = await store.allEnvelopes().contains { envelope in
            if case let .participantJoined(identity) = envelope.event { return identity.verificationState == .verified }
            return false
        }
        #expect(recordedVerified)
    }

    /// A declined wallet signature must not be reported as a failed join.
    ///
    /// `joinSession` has already persisted the invite, registered the runtime, and subscribed to the
    /// relay topic by the time the ownership proof runs — so the session is **live** regardless of how
    /// the proof turns out. Collapsing the two into `.failed` told the user "something went wrong with
    /// this shared session" while their device sat in that session receiving events as an unverified
    /// participant, with no indication of the real state or how to finish verifying.
    @Test("A declined wallet signature keeps the session joined and reports it as unverified")
    func declinedSignatureStillJoins() async throws {
        let store = SocialEventLogStore()
        let assembly = SocialRelayAssembly(
            composition: SocialRelayComposition(
                configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
                eventLogStore: store
            ),
            collaboratorsFactory: { _ in
                SocialRelayCollaborators(transport: NoopQueueTransport(), inboundSource: NoopInboundSource())
            }
        )
        let verifier = SocialJoinVerificationService(
            // The user declines the prompt.
            verifier: SocialWalletJoinVerifier(walletVerifier: FakeOwnershipVerifier(result: false)),
            eventLogStore: store
        )
        let model = SocialInviteExchangeModel(
            assembly: assembly,
            participantID: account,
            joinVerifier: verifier,
            walletSessionIDProvider: { WalletSessionID(rawValue: "s") }
        )

        let invite = SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "host")
        await model.importInvite(code: try SocialInviteCoding.encode(invite))

        // Joined, not failed — and carrying a notice that explains the unverified state.
        guard case let .joined(sessionID, notice) = model.state else {
            Issue.record("expected joined-with-notice, got \(model.state)")
            return
        }
        #expect(sessionID == invite.sessionID)
        #expect(notice != nil)
        // The session really is live: the invite was persisted and the runtime registered.
        #expect(await store.allInvites().map(\.sessionID) == [invite.sessionID])
        #expect(await assembly.activeSessionIDs() == [invite.sessionID])
        // And nothing was recorded as verified.
        let recordedVerified = await store.allEnvelopes().contains { envelope in
            if case let .participantJoined(identity) = envelope.event { return identity.verificationState == .verified }
            return false
        }
        #expect(recordedVerified == false)
    }

    /// Re-scanning a QR for a session this device already joined is the ordinary case, not an error.
    ///
    /// Nonces are consumed in this device's *local* validator, keyed by session+nonce, so the second
    /// import hits `replayedNonce` — which used to surface as `.failed`, reporting a perfectly healthy,
    /// already-verified session as a failed join.
    @Test("Re-importing an already-joined invite reports success, not a replay failure")
    func reimportOfJoinedInviteSucceeds() async throws {
        let store = SocialEventLogStore()
        let assembly = SocialRelayAssembly(
            composition: SocialRelayComposition(
                configuration: SocialFeatureConfiguration(infoDictionary: ["AURALIS_SOCIAL_RELAY_ENABLED": true]),
                eventLogStore: store
            ),
            collaboratorsFactory: { _ in
                SocialRelayCollaborators(transport: NoopQueueTransport(), inboundSource: NoopInboundSource())
            }
        )
        let verifier = SocialJoinVerificationService(
            verifier: SocialWalletJoinVerifier(walletVerifier: FakeOwnershipVerifier(result: true)),
            eventLogStore: store
        )
        let model = SocialInviteExchangeModel(
            assembly: assembly,
            participantID: account,
            joinVerifier: verifier,
            walletSessionIDProvider: { WalletSessionID(rawValue: "s") }
        )
        let code = try SocialInviteCoding.encode(
            SocialInviteMint.mint(sessionID: UUID(), inviterParticipantID: "host")
        )

        await model.importInvite(code: code)
        await model.importInvite(code: code)

        guard case let .joined(_, notice) = model.state else {
            Issue.record("expected joined on re-import, got \(model.state)")
            return
        }
        // Already verified on this device, so there is nothing to warn about.
        #expect(notice == nil)
        #expect(await store.allInvites().count == 1)
    }
}

private struct FakeOwnershipVerifier: SocialWalletOwnershipVerifying {
    let result: Bool
    func verifyOwnership(
        of address: String,
        chain: WalletChain,
        in sessionId: WalletSessionID,
        statement: String,
        expiryDate: Date
    ) async throws -> Bool {
        result
    }
}

private actor NoopQueueTransport: SocialRelayTransporting {
    func subscribe(topic: String) async throws { }
    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws { }
}

private struct NoopInboundSource: SocialRelayInboundStreaming {
    func inboundMessages() async -> AsyncStream<SocialRelayInboundMessage> { AsyncStream { $0.finish() } }
}
