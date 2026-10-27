import Foundation
import AuralisOperators
import WalletAdapters

/// P3 — turns a wallet-ownership check into a recorded, verified participant.
///
/// Verifies that the joiner controls `caip10Account` by having the wallet sign the invite's join
/// challenge (via ``SocialWalletJoinVerifier`` → the app's `WalletConnector`), then records a *verified*
/// `participantJoined` identity into the durable event log so the projection lets that participant author
/// binding events (votes, queue mutations). Verification failure records nothing and rethrows, so an
/// unproven joiner stays a pending invitee. The nonce is consumed to reject replay.
///
/// The live signature prompt is device-only; this service is exercised in tests through a fake
/// ``SocialWalletOwnershipVerifying``.
actor SocialJoinVerificationService {
    private let verifier: SocialWalletJoinVerifier
    private let eventLogStore: SocialEventLogStore
    private var validator: SocialJoinChallengeValidator
    /// Consumption keys with a verification in flight right now.
    ///
    /// The validator's own `consumedNonces` is only updated *after* the wallet round-trip, and this
    /// actor is reentrant across that suspension — so two overlapping calls (a double-tapped Join, or a
    /// scan racing a paste) each saw an unconsumed nonce, each passed the replay guard, and the later
    /// write-back erased the earlier one's consumption. Reserving the key synchronously before the first
    /// `await` is what actually makes the nonce single-use.
    private var inFlightConsumptionKeys: Set<String> = []

    init(
        verifier: SocialWalletJoinVerifier,
        eventLogStore: SocialEventLogStore,
        validator: SocialJoinChallengeValidator = SocialJoinChallengeValidator()
    ) {
        self.verifier = verifier
        self.eventLogStore = eventLogStore
        self.validator = validator
    }

    @discardableResult
    func verifyAndRecordJoin(
        invite: SocialInvite,
        caip10Account: String,
        displayName: String,
        role: SharedRole = .collaborator,
        walletSessionID: WalletSessionID,
        verificationMethod: String = SocialParticipantProof.connectorVerified,
        now: Date = .now
    ) async throws -> SocialParticipantProof {
        // Claim the nonce *before* the first suspension. See `inFlightConsumptionKeys`.
        let consumptionKey = SocialJoinChallengeValidator.consumptionKey(
            sessionID: invite.sessionID,
            nonce: invite.nonce
        )
        guard !inFlightConsumptionKeys.contains(consumptionKey) else {
            throw SocialJoinChallengeError.replayedNonce
        }
        inFlightConsumptionKeys.insert(consumptionKey)
        defer { inFlightConsumptionKeys.remove(consumptionKey) }

        // Copy-in/copy-out around the async verify: an actor-isolated property can't be passed `inout`
        // across a suspension. Consumed nonces are written back so replay stays rejected across calls.
        //
        // Note the validator is in-memory only, so `consumedNonces` does not survive a relaunch. The
        // durable defence against a cross-launch replay is the projection, which refuses a second
        // `participantJoined` for an identity it already holds; this validator is the first line, not
        // the only one.
        var validator = self.validator
        let proof: SocialParticipantProof
        do {
            proof = try await verifier.verifyJoin(
                invite: invite,
                caip10Account: caip10Account,
                sessionID: walletSessionID,
                verificationMethod: verificationMethod,
                now: now,
                validator: &validator
            )
        } catch {
            mergeConsumedNonces(from: validator)
            throw error
        }
        mergeConsumedNonces(from: validator)

        let identity = SocialParticipantIdentity(
            participantID: caip10Account,
            caip10Account: caip10Account,
            displayName: displayName,
            role: role,
            verificationState: .verified,
            joinedAt: now,
            proofID: proof.id
        )
        await eventLogStore.enqueueOutbound(
            SocialEventEnvelope(
                sessionID: invite.sessionID,
                authorParticipantID: caip10Account,
                authorCAIP10Account: caip10Account,
                createdAt: now,
                event: .participantJoined(identity)
            )
        )
        return proof
    }

    /// Folds a copied-out validator's consumed nonces back in, by union rather than assignment.
    ///
    /// `inFlightConsumptionKeys` serialises only calls sharing a consumption *key*. Two joins with
    /// different nonces run concurrently by design, and each copies the validator, awaits the wallet,
    /// and writes back — so a plain `self.validator = validator` let the later writer restore a
    /// snapshot taken before the earlier one's consumption, re-opening that nonce to replay.
    ///
    /// Union is the correct merge because consumption is monotonic: a nonce is only ever added, never
    /// released, so no concurrent ordering can make forgetting one correct.
    private func mergeConsumedNonces(from copy: SocialJoinChallengeValidator) {
        validator = SocialJoinChallengeValidator(
            consumedNonces: validator.consumedNonces.union(copy.consumedNonces)
        )
    }
}
