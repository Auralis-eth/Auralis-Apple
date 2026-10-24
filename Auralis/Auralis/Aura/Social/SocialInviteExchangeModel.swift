import Foundation
import Observation
import SocialCore
import WalletConnectorKit

/// Drives the host/join invite-exchange surface for one shared session. UI-framework-free so it can be
/// unit-tested against a ``SocialRelayAssembly`` built with fake collaborators.
@MainActor
@Observable
final class SocialInviteExchangeModel {
    enum State: Equatable {
        case idle
        /// Relay social is off for this build — nothing to host or join.
        case disabled
        /// Hosting: the invite to hand out and its encoded, shareable form.
        case hosting(invite: SocialInvite, code: String)
        /// Joined a session from an imported invite.
        ///
        /// `verificationNotice` is non-nil when the session is live but the *optional* wallet-ownership
        /// proof did not complete — the participant is joined and receiving events, just not verified.
        /// The two were previously collapsed into `.failed`, which reported "join failed" for a session
        /// that was already persisted, subscribed, and flowing: declining the wallet signature prompt
        /// left the user looking at an error while their device sat in the session as an unverified
        /// participant, with no indication that was the state or how to finish.
        case joined(sessionID: UUID, verificationNotice: String?)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let assembly: SocialRelayAssembly
    private let participantID: String
    /// Optional P3 wiring: when present (and the participant id is a CAIP-10 account with an active
    /// wallet session), a join runs a wallet-signature challenge and records a verified participant.
    private let joinVerifier: SocialJoinVerificationService?
    /// Resolves the joiner's live wallet session at join time. A closure (not a stored id) because the
    /// live lookup is async and the connected session can change after the model is built.
    private let walletSessionIDProvider: (@Sendable () async -> WalletSessionID?)?

    init(
        assembly: SocialRelayAssembly,
        participantID: String,
        joinVerifier: SocialJoinVerificationService? = nil,
        walletSessionIDProvider: (@Sendable () async -> WalletSessionID?)? = nil
    ) {
        self.assembly = assembly
        self.participantID = participantID
        self.joinVerifier = joinVerifier
        self.walletSessionIDProvider = walletSessionIDProvider
    }

    /// The encoded invite string when hosting, for QR rendering / copy / share.
    var shareableCode: String? {
        if case let .hosting(_, code) = state { return code }
        return nil
    }

    /// Mints and starts hosting `sessionID`, exposing the shareable invite code. Sets `.disabled` when
    /// the relay flag is off, `.failed` on any error.
    func host(sessionID: UUID) async {
        do {
            guard let invite = try await assembly.hostSession(sessionID: sessionID, inviterParticipantID: participantID) else {
                state = .disabled
                return
            }
            state = .hosting(invite: invite, code: try SocialInviteCoding.encode(invite))
        } catch {
            state = .failed(Self.userFacingMessage(for: error))
        }
    }

    /// Imports a scanned/pasted invite code and joins its session. Sets `.disabled` when the relay flag
    /// is off, `.failed` on a malformed code or join error.
    func importInvite(code: String) async {
        do {
            let invite = try SocialInviteCoding.decode(code)
            guard try await assembly.joinSession(invite: invite) else {
                state = .disabled
                return
            }
            // Past this point the session is **live**: the invite is persisted, the runtime is
            // registered, and the relay topic is subscribed. Everything below is the optional P3
            // ownership proof, whose failure must not be reported as a failed join.
            var verificationNotice: String?

            // P3: prove wallet ownership of the CAIP-10 identity and record a verified participant. Only
            // attempted when a verifier is present, the id is a real account, and the joiner's wallet
            // session resolves; otherwise the local (unverified) join stands.
            if let joinVerifier, SocialCAIP10.isCAIP10(participantID),
               let walletSessionID = await walletSessionIDProvider?() {
                do {
                    try await joinVerifier.verifyAndRecordJoin(
                        invite: invite,
                        caip10Account: participantID,
                        displayName: participantID,
                        walletSessionID: walletSessionID
                    )
                } catch SocialJoinChallengeError.replayedNonce {
                    // Nonces are consumed in this device's *local* validator, keyed by session+nonce,
                    // so a replay can only mean this device already ran the challenge for this invite
                    // — the ordinary outcome of re-scanning a QR for a session joined earlier. The
                    // participant is already verified; reporting an error for it told the user a
                    // perfectly healthy session had failed to join.
                    verificationNotice = nil
                } catch {
                    verificationNotice = Self.verificationNotice(for: error)
                }
            }
            state = .joined(sessionID: invite.sessionID, verificationNotice: verificationNotice)
        } catch {
            state = .failed(Self.userFacingMessage(for: error))
        }
    }

    /// Copy for a join that succeeded while its optional wallet-ownership proof did not.
    ///
    /// Deliberately distinct from ``userFacingMessage(for:)``: it has to convey "you are in the
    /// session, but unverified" rather than "that didn't work", because the first is true and the
    /// second would send the user to re-scan an invite they have already used.
    private static func verificationNotice(for error: Error) -> String {
        let suffix = "You're in the session, but other members will see you as unverified. "
            + "You can verify your wallet from the session's details."
        switch error {
        case SocialJoinChallengeError.signatureRejected:
            return "Wallet signature declined. " + suffix
        case SocialJoinChallengeError.wrongAccount:
            return "That signature came from a different wallet than the one you joined with. " + suffix
        case SocialJoinChallengeError.expiredInvite:
            return "This invite expired before your wallet could sign. " + suffix
        default:
            return "Couldn't verify your wallet for this session. " + suffix
        }
    }

    /// Maps an error to copy a person can act on.
    ///
    /// `String(describing:)` rendered raw internal cases into the UI — a scanned bad QR showed
    /// "malformedPayload". Types that define `errorDescription` already carry written copy, so those
    /// pass through; anything else gets a generic message rather than leaking an enum case name.
    private static func userFacingMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription { return localized }
        if error is SocialInviteCodingError {
            return "That invite code isn't valid. Ask the host to re-share it."
        }
        return "Something went wrong with this shared session. Try again, or ask the host for a new invite."
    }
}
