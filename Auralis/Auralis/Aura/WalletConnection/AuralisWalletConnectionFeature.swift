import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import CoreImage.CIFilterBuiltins
import Foundation
import Observation
import Security
import SwiftData
import SwiftUI
import UIKit
import WalletConnectorKit

struct AuralisWalletConnectionConfig: Sendable {
    let projectID: String
    let metadata: WalletConnectionMetadata
    let callbackURL: URL

    init(bundle: Bundle = .main) throws {
        guard
            let rawProjectID = bundle.object(forInfoDictionaryKey: "AURALIS_WALLETCONNECT_PROJECT_ID") as? String,
            !rawProjectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !rawProjectID.hasPrefix("$(")
        else {
            throw WalletConnectionError.unavailable("WalletConnect project ID is not configured.")
        }

        self.projectID = rawProjectID
        self.callbackURL = URL(string: "auraplay://walletconnect")!
        self.metadata = WalletConnectionMetadata(
            appName: "AuraPlay",
            appDescription: "NFT media player",
            appURL: URL(string: "https://auraplay.app")!,
            iconURL: URL(string: "https://auraplay.app/icon.png"),
            redirect: WalletConnectionRedirect(native: "auraplay://walletconnect", linkMode: true)
        )
    }
}

/// Resolves the shared Keychain access group for the WalletConnector stores at
/// runtime, so no team id is hard-coded in source.
///
/// The group base name is `com.auraplay.walletconnect.shared`; the app-identifier
/// (team) prefix is discovered by probing the Keychain for the access group the
/// system assigns a default item, then taking the segment before the first `.`.
///
/// This shared group is how the app and its extension(s) read the same
/// WalletConnect session key material — an App Group container does **not** share
/// Keychain items. It therefore requires **both** the app target and every
/// consuming extension target to enable **Signing & Capabilities → Keychain
/// Sharing** with the matching group (`$(AppIdentifierPrefix)com.auraplay.walletconnect.shared`).
/// Until that entitlement is present the store operations fail closed (the stores
/// already handle a missing entitlement gracefully); once it is present, sessions
/// become visible cross-process.
///
/// Returns `nil` if the prefix cannot be probed, in which case the stores fall
/// back to the app's private default group (no sharing) rather than breaking.
enum WalletConnectKeychainAccessGroup {
    static let baseIdentifier = "com.auraplay.walletconnect.shared"

    /// Resolved once per process.
    static let resolved: String? = resolve()

    private static func resolve() -> String? {
        guard let prefix = appIdentifierPrefix() else { return nil }
        return "\(prefix).\(baseIdentifier)"
    }

    /// The team/app-identifier prefix (e.g. `ABCDE12345`) discovered by adding a
    /// throwaway Keychain item with no explicit access group and reading back the
    /// group the system assigned. The prefix is the segment before the first `.`.
    /// The probe does not require the Keychain Sharing entitlement, so the prefix
    /// resolves even before the capability is wired up.
    private static func appIdentifierPrefix() -> String? {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.auraplay.walletconnect",
            kSecAttrAccount as String: "walletconnect-accessgroup-probe",
        ]
        // Clean slate, then add + read back the assigned access group.
        SecItemDelete(baseQuery as CFDictionary)
        defer { SecItemDelete(baseQuery as CFDictionary) }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = Data([0x00])
        addQuery[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        guard SecItemAdd(addQuery as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any],
              let group = attributes[kSecAttrAccessGroup as String] as? String,
              let firstDot = group.firstIndex(of: ".") else {
            return nil
        }
        return String(group[group.startIndex..<firstDot])
    }
}

struct UIApplicationWalletOpener: WalletApplicationOpening {
    func canOpenURL(_ url: URL) async -> Bool {
        await MainActor.run {
            UIApplication.shared.canOpenURL(url)
        }
    }

    func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                UIApplication.shared.open(url, options: [:]) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

@MainActor
final class AuralisWalletAccountAdapter {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func upsert(_ walletAddress: WalletSessionAddress, selectedAt: Date) throws -> EOAccount {
        let address = canonicalAddress(walletAddress.account.address, chain: walletAddress.chain)
        let chain = walletAddress.chain.auralisChain
        let account = try existingAccount(address: address) ?? EOAccount(
            address: address,
            access: .wallet,
            name: nil,
            source: .walletConnect,
            addedAt: selectedAt,
            lastSelectedAt: selectedAt
        )

        if account.modelContext == nil {
            modelContext.insert(account)
        }

        account.access = .wallet
        account.source = .walletConnect
        account.currentChain = chain
        account.preferredChain = chain
        account.lastSelectedAt = selectedAt
        try modelContext.save()
        return account
    }

    func deactivate(address: String, chain: WalletChain, at date: Date) throws {
        guard let account = try existingAccount(address: canonicalAddress(address, chain: chain)) else {
            return
        }

        account.access = .readonly
        account.lastSelectedAt = date
        try modelContext.save()
    }

    func mostRecentlyUsedActiveAddress(excluding address: String?) throws -> String? {
        let excluded = address?.lowercased()
        let accounts = try modelContext.fetch(FetchDescriptor<EOAccount>())
        return accounts
            .filter { $0.access?.canSign == true }
            .filter { $0.address.lowercased() != excluded }
            .sorted { ($0.lastSelectedAt ?? $0.addedAt) > ($1.lastSelectedAt ?? $1.addedAt) }
            .first?
            .address
    }

    private func existingAccount(address: String) throws -> EOAccount? {
        let descriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate { account in
                account.address == address
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func canonicalAddress(_ address: String, chain: WalletChain) -> String {
        switch chain {
        case .ethereum, .polygon, .base, .optimism, .arbitrum:
            address.lowercased()
        case .solana:
            address
        }
    }
}

@MainActor
@Observable
final class AuralisWalletConnectionService {
    enum Phase: Equatable {
        case idle
        case connecting(String)
        case awaitingApproval(String)
        case connected(String)
        case failed(String)
    }

    private let connector: any WalletConnector
    private let accountAdapter: AuralisWalletAccountAdapter
    private let topicStore: any WalletSessionTopicStoring
    private let activeWalletStore: any ActiveWalletStoring

    var phase: Phase = .idle
    var latestPairingPayload: String?
    var connectedAddress: String?

    let providers: [ThirdPartyWalletProvider] = WalletConnectorCatalog.defaultProviders

    init(modelContext: ModelContext, bundle: Bundle = .main) {
        // Shared Keychain access group so an extension can read the same
        // WalletConnect sessions/relay identity. All three keychain stores must
        // use the *same* group (topic index, session-state, relay identity), or
        // the extension sees a partial view. `nil` (probe failed) falls back to
        // the app's private default group.
        let accessGroup = WalletConnectKeychainAccessGroup.resolved
        self.accountAdapter = AuralisWalletAccountAdapter(modelContext: modelContext)
        self.topicStore = KeychainWalletSessionTopicStore(accessGroup: accessGroup)
        self.activeWalletStore = UserDefaultsActiveWalletStore()

        do {
            let config = try AuralisWalletConnectionConfig(bundle: bundle)
            let relay = WalletConnectIRNRelayClient(
                configuration: WalletConnectRelayConfiguration(projectID: config.projectID),
                authProvider: WalletConnectKeychainRelayAuthProvider(accessGroup: accessGroup)
            )
            let transport = WalletConnectIRNTransportClient(
                relayClient: relay,
                stateStore: KeychainWalletConnectSessionStateStore(accessGroup: accessGroup)
            )
            self.connector = WalletConnectDAppConnector(
                transport: transport,
                launcher: DeepLinkWalletLauncher(opener: UIApplicationWalletOpener()),
                metadata: config.metadata,
                callbackURL: config.callbackURL,
                // Real secp256k1 recovery so EVM ownership verification succeeds
                // instead of failing closed; also lifts readiness to productionReady.
                cryptoProvider: Web3SwiftWalletConnectorCryptoProvider()
            )
        } catch {
            self.connector = WalletConnectDAppConnector(
                transport: UnavailableWalletTransportClient(message: error.localizedDescription),
                metadata: WalletConnectionMetadata(
                    appName: "AuraPlay",
                    appDescription: "NFT media player",
                    appURL: URL(string: "https://auraplay.app")!
                ),
                cryptoProvider: Web3SwiftWalletConnectorCryptoProvider()
            )
            self.phase = .failed(error.localizedDescription)
        }

        observeConnectorEvents()
    }

    /// Test seam. Injects the connector and stores directly so interaction tests
    /// can drive the connect → settle → remove flows without a live relay, the
    /// Keychain, or `UserDefaults`. The app uses `init(modelContext:bundle:)`.
    init(
        connector: any WalletConnector,
        accountAdapter: AuralisWalletAccountAdapter,
        topicStore: any WalletSessionTopicStoring,
        activeWalletStore: any ActiveWalletStoring,
        phase: Phase = .idle
    ) {
        self.connector = connector
        self.accountAdapter = accountAdapter
        self.topicStore = topicStore
        self.activeWalletStore = activeWalletStore
        self.phase = phase
        observeConnectorEvents()
    }

    func connect(with provider: ThirdPartyWalletProvider?) async {
        let providerName = provider?.displayName ?? "WalletConnect"
        phase = .connecting(providerName)

        do {
            let start = try await connector.connect(
                proposal: .defaultV1,
                wallet: provider
            )
            latestPairingPayload = start.qrPayload
            phase = .awaitingApproval(providerName)
        } catch WalletConnectionError.walletNotInstalled {
            await connectWithGenericPairing(label: providerName)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func connectWithQR() async {
        await connect(with: nil)
    }

    func remove(account: EOAccount) async {
        let chain = WalletChain(auralisChain: account.currentChain)
        do {
            if let topic = try await topicStore.load(walletAddress: account.address) {
                try await connector.disconnect(sessionId: WalletSessionID(rawValue: topic.rawValue))
            }
            try await topicStore.delete(walletAddress: account.address)
            try accountAdapter.deactivate(address: account.address, chain: chain, at: Date())

            if activeWalletStore.get()?.caseInsensitiveCompare(account.address) == .orderedSame {
                if let fallback = try accountAdapter.mostRecentlyUsedActiveAddress(excluding: account.address) {
                    activeWalletStore.set(fallback)
                } else {
                    activeWalletStore.clear()
                }
            }
            phase = .idle
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func setActive(account: EOAccount) {
        activeWalletStore.set(account.address)
    }

    func activeAddress() -> String? {
        activeWalletStore.get()
    }

    func cancel() {
        phase = .idle
    }

    func handleCallback(url: URL) async {
        do {
            try await connector.handleCallback(url: url)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func connectWithGenericPairing(label: String) async {
        do {
            let start = try await connector.connect(proposal: .defaultV1, wallet: nil)
            latestPairingPayload = start.qrPayload
            phase = .awaitingApproval(label)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func observeConnectorEvents() {
        Task { [weak self, connector] in
            for await event in connector.events {
                await self?.handle(event)
            }
        }
    }

    private func handle(_ event: WalletConnectorEvent) async {
        switch event {
        case .pairingCreated(let uri):
            latestPairingPayload = uri.absoluteString
        case .sessionSettled(let session):
            await persist(session)
        case .sessionRejected(let error):
            phase = .failed(error.localizedDescription)
        case .sessionDeleted:
            if let address = connectedAddress {
                try? await topicStore.delete(walletAddress: address)
            }
            phase = .idle
            latestPairingPayload = nil
            connectedAddress = nil
        case .requestExpired(let requestID):
            phase = .failed("Wallet request \(requestID.rawValue) expired.")
        case .responseReceived, .socketStatusChanged:
            break
        }
    }

    private func persist(_ session: WalletConnectorSession) async {
        let addresses = WalletSessionAddressExtractor.extract(from: session)
        guard !addresses.isEmpty else {
            phase = .failed("The wallet approved the connection, but no supported address was returned.")
            return
        }

        do {
            for address in addresses {
                let account = try accountAdapter.upsert(address, selectedAt: Date())
                try await topicStore.save(topic: session.topic, walletAddress: account.address)
                activeWalletStore.set(account.address)
                connectedAddress = account.address
            }
            phase = .connected(connectedAddress ?? addresses.last!.account.address)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private actor UnavailableWalletTransportClient: WalletTransportClient {
    private let message: String

    init(message: String) {
        self.message = message
    }

    func createPairing(request: WalletPairingRequest) async throws -> WalletPairing {
        throw WalletConnectionError.unavailable(message)
    }

    func disconnect(topic: WalletPairingTopic) async throws {}
    func request(_ request: WalletRequest, topic: WalletPairingTopic) async throws -> WalletResponse {
        throw WalletConnectionError.unavailable(message)
    }
    func sessions() async throws -> [WalletSession] { [] }
    nonisolated func events() -> AsyncStream<WalletTransportEvent> { AsyncStream { $0.finish() } }
}

private extension WalletChain {
    var auralisChain: Chain {
        switch self {
        case .ethereum:
            .ethMainnet
        case .polygon:
            .polygonMainnet
        case .base:
            .baseMainnet
        case .optimism:
            .optMainnet
        case .arbitrum:
            .arbMainnet
        case .solana:
            .solanaMainnet
        }
    }

    init(auralisChain: Chain) {
        switch auralisChain {
        case .polygonMainnet:
            self = .polygon
        case .baseMainnet:
            self = .base
        case .optMainnet:
            self = .optimism
        case .arbMainnet, .arbNovaMainnet:
            self = .arbitrum
        case .solanaMainnet, .solanaDevnetTestnet:
            self = .solana
        default:
            self = .ethereum
        }
    }
}
