import Foundation
import MusicFeature
import SocialCore
import SwiftData
import WalletConnectorKit

/// App composition for Social v1: builds a ``SocialRelayAssembly`` wired to the app's shared, durable
/// social event log and (only when the relay flag is on) the live WalletConnect/IRN relay client.
///
/// Everything is gated on `AURALIS_SOCIAL_RELAY_ENABLED`. With the flag off, or with no relay project
/// configured, the assembly is built with inert collaborators that are never invoked (the composition
/// returns `nil` before touching them), so no socket is ever opened.
///
/// **The flag is `YES` in both `Auralis-Debug.xcconfig` and `Auralis-Release.xcconfig`** — the relay is
/// live in shipping builds, deliberately. Do not read the gate as "this code is unreachable in
/// production"; every path below runs against a relay that is treated as untrusted.
@MainActor
enum SocialAssembly {
    /// Builds an assembly reusing the shared `RuntimeHost`'s durable `SocialEventLogStore`, so relay
    /// state and Mission Control's projected state read the same append-only log.
    static func make(modelContext: ModelContext, modeState: ModeState, bundle: Bundle = .main) -> SocialRelayAssembly {
        let host = RuntimeAssembly.sharedHost(
            modelContext: modelContext,
            cryptoModeProvider: { modeState.mode },
            cryptoModeSetter: { modeState.setMode($0) }
        )
        return make(
            eventLogStore: host.socialEventLogStore,
            configuration: SocialFeatureConfiguration(),
            diagnostics: ReceiptBackedSocialRelayDiagnostics(host: host),
            bundle: bundle
        )
    }

    /// Assembles everything the invite-exchange UI needs for one build/account: a relay assembly with
    /// collaborative-queue → AuraPlay wiring (P4), and — when a wallet connection is available and the
    /// participant id is a real CAIP-10 account — the P3 join verifier plus a resolver for the account's
    /// live wallet session. Reuses the shared `RuntimeHost`'s durable event log so relay, queue, and
    /// Mission Control all read the same append-only log. Everything stays gated by the relay flag.
    static func makeInviteExchange(
        modelContext: ModelContext,
        modeState: ModeState,
        accountAddress: String?,
        chainID: Int?,
        auraPlayModelContainer: ModelContainer?,
        walletConnectionService: AuralisWalletConnectionService?,
        bundle: Bundle = .main
    ) -> SocialInviteExchangeComposition {
        let host = RuntimeAssembly.sharedHost(
            modelContext: modelContext,
            cryptoModeProvider: { modeState.mode },
            cryptoModeSetter: { modeState.setMode($0) }
        )
        let eventLogStore = host.socialEventLogStore
        let playlistManager = auraPlayModelContainer.map { AuraPlayPlaylistService(modelContainer: $0) }
        let assembly = make(
            eventLogStore: eventLogStore,
            configuration: SocialFeatureConfiguration(),
            diagnostics: ReceiptBackedSocialRelayDiagnostics(host: host),
            playlistManager: playlistManager,
            bundle: bundle
        )
        let participantID = participantID(address: accountAddress, chainID: chainID)

        // P3: a verified join needs a live wallet session for a real on-chain identity. Absent either,
        // the local (unverified) join stands and the verifier is simply not supplied.
        var joinVerifier: SocialJoinVerificationService?
        var walletSessionIDProvider: (@Sendable () async -> WalletSessionID?)?
        if let walletConnectionService, let accountAddress, SocialCAIP10.isCAIP10(participantID) {
            joinVerifier = makeJoinVerifier(
                ownershipVerifier: liveOwnershipVerifier(connector: walletConnectionService.walletConnector),
                eventLogStore: eventLogStore
            )
            walletSessionIDProvider = { await walletConnectionService.walletSessionID(forAddress: accountAddress) }
        }

        return SocialInviteExchangeComposition(
            assembly: assembly,
            participantID: participantID,
            joinVerifier: joinVerifier,
            walletSessionIDProvider: walletSessionIDProvider
        )
    }

    static func make(
        eventLogStore: SocialEventLogStore,
        configuration: SocialFeatureConfiguration,
        diagnostics: any SocialRelayDiagnostics = NoopSocialRelayDiagnostics(),
        playlistManager: (any AuraPlayPlaylistManaging)? = nil,
        bundle: Bundle = .main
    ) -> SocialRelayAssembly {
        // P4: wire collaborative queue → AuraPlay only when a live playlist manager is available.
        let queueFactory = playlistManager.map(Self.queuePlaylistTargetFactory(playlistManager:))
        let composition = SocialRelayComposition(
            configuration: configuration,
            eventLogStore: eventLogStore,
            diagnostics: diagnostics
        )
        guard configuration.relayEnabled, let relayClient = try? makeRelayClient(bundle: bundle) else {
            // Disabled (or no relay config): the composition returns nil before the factory is invoked.
            return SocialRelayAssembly(
                composition: composition,
                collaboratorsFactory: { _ in
                    SocialRelayCollaborators(
                        transport: InertSocialRelayTransport(),
                        inboundSource: InertSocialRelayInboundSource()
                    )
                },
                queuePlaylistTargetFactory: queueFactory
            )
        }
        return SocialRelayAssembly.live(
            configuration: configuration,
            eventLogStore: eventLogStore,
            relayClient: relayClient,
            diagnostics: diagnostics,
            queuePlaylistTargetFactory: queueFactory
        )
    }

    // MARK: - Collaborative queue → AuraPlay (P4)

    /// Builds the per-session queue-target factory: each shared session reconciles a *dedicated* AuraPlay
    /// playlist (created once, remembered per session) to its accepted collaborative queue.
    static func queuePlaylistTargetFactory(
        playlistManager: any AuraPlayPlaylistManaging
    ) -> SocialQueuePlaylistTargetFactory {
        { invite in
            guard let playlistID = await sharedPlaylistID(for: invite.sessionID, playlistManager: playlistManager) else {
                return nil
            }
            return AuraPlayPlaylistQueueTarget(playlistManager: playlistManager, playlistID: playlistID)
        }
    }

    /// A stable AuraPlay playlist bound to `sessionID` — created on first use and remembered in
    /// `UserDefaults`, so a shared session's collaborative queue always reconciles the same playlist
    /// across launches. Returns `nil` when AuraPlay storage cannot mint one.
    static func sharedPlaylistID(
        for sessionID: UUID,
        playlistManager: any AuraPlayPlaylistManaging
    ) async -> String? {
        let key = UserDefaultsSocialCoordinationResetter.sessionPlaylistKeyPrefix + sessionID.uuidString
        if let existing = UserDefaults.standard.string(forKey: key),
           (try? await playlistManager.fetchPlaylistSnapshot(id: existing)) != nil {
            // Remembered playlist still exists — reuse it.
            return existing
        }
        guard let created = try? await playlistManager.createID(
            name: "Shared Session \(sessionID.uuidString.prefix(8))",
            at: .now
        ) else {
            return nil
        }
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    /// The participant id to author invites/events under: the connected wallet's CAIP-10 account when
    /// one is available, otherwise a stable per-install fallback id. Using the CAIP-10 means a hosted
    /// invite carries a real on-chain author that join verification (`SocialWalletJoinVerifier`, P3) can
    /// later prove ownership of — the live signature challenge remains device-only.
    static func participantID(address: String?, chainID: Int?) -> String {
        if let address, let chainID, let caip10 = SocialCAIP10.eip155(address: address, chainID: chainID) {
            return caip10
        }
        return localParticipantID
    }

    /// A stable per-install fallback participant id for when no wallet account is available (e.g.
    /// observe-only). Sufficient to author/attribute events on one device.
    static var localParticipantID: String {
        let key = UserDefaultsSocialCoordinationResetter.localParticipantIDKey
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    // MARK: - Join verification (P3)

    /// Builds a live join verifier from an ownership-verifying seam. Callers that hold the app's
    /// `WalletConnector` pass ``liveOwnershipVerifier(connector:)``; tests inject a fake.
    static func makeJoinVerifier(
        ownershipVerifier: any SocialWalletOwnershipVerifying,
        eventLogStore: SocialEventLogStore,
        validator: SocialJoinChallengeValidator = SocialJoinChallengeValidator()
    ) -> SocialJoinVerificationService {
        SocialJoinVerificationService(
            verifier: SocialWalletJoinVerifier(walletVerifier: ownershipVerifier),
            eventLogStore: eventLogStore,
            validator: validator
        )
    }

    /// Adapts the app's live `WalletConnector` into the ownership-verifying seam the join challenge uses.
    /// The verifier resolves the wallet's signature against the CAIP-10 account before a participant is
    /// marked verified — a device-only prompt.
    static func liveOwnershipVerifier(connector: any WalletConnector) -> any SocialWalletOwnershipVerifying {
        WalletConnectorSocialOwnershipVerifier(connector: connector)
    }

    private static func makeRelayClient(bundle: Bundle) throws -> WalletConnectIRNRelayClient {
        let config = try AuralisWalletConnectionConfig(bundle: bundle)
        return WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: config.projectID),
            authProvider: WalletConnectKeychainRelayAuthProvider(accessGroup: WalletConnectKeychainAccessGroup.resolved)
        )
    }
}

/// Everything the invite-exchange UI needs for one build/account: the relay assembly (with queue →
/// AuraPlay wiring), the participant id to author under, and the optional P3 join-verification seam.
struct SocialInviteExchangeComposition {
    let assembly: SocialRelayAssembly
    let participantID: String
    let joinVerifier: SocialJoinVerificationService?
    let walletSessionIDProvider: (@Sendable () async -> WalletSessionID?)?
}

/// No-op transport used only to satisfy the collaborators factory when relay social is disabled; the
/// composition returns `nil` before it is ever used.
struct InertSocialRelayTransport: SocialRelayTransporting {
    func subscribe(topic: String) async throws { }
    func publish(topic: String, message: String, tag: Int, ttl: Int) async throws { }
}

/// No-op inbound source (an immediately-finished stream) — see ``InertSocialRelayTransport``.
struct InertSocialRelayInboundSource: SocialRelayInboundStreaming {
    func inboundMessages() async -> AsyncStream<SocialRelayInboundMessage> {
        AsyncStream { $0.finish() }
    }
}
