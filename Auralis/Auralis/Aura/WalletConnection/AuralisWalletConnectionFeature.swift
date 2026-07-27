import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import CoreImage.CIFilterBuiltins
import Foundation
import Observation
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

    private let connector: WalletConnectDAppConnector
    private let accountAdapter: AuralisWalletAccountAdapter
    private let topicStore: KeychainWalletSessionTopicStore
    private let activeWalletStore: UserDefaultsActiveWalletStore

    var phase: Phase = .idle
    var latestPairingPayload: String?
    var connectedAddress: String?

    let providers: [ThirdPartyWalletProvider] = WalletConnectorCatalog.defaultProviders

    init(modelContext: ModelContext, bundle: Bundle = .main) {
        self.accountAdapter = AuralisWalletAccountAdapter(modelContext: modelContext)
        self.topicStore = KeychainWalletSessionTopicStore()
        self.activeWalletStore = UserDefaultsActiveWalletStore()

        do {
            let config = try AuralisWalletConnectionConfig(bundle: bundle)
            let relay = WalletConnectIRNRelayClient(
                configuration: WalletConnectRelayConfiguration(projectID: config.projectID)
            )
            let transport = WalletConnectIRNTransportClient(relayClient: relay)
            self.connector = WalletConnectDAppConnector(
                transport: transport,
                launcher: DeepLinkWalletLauncher(opener: UIApplicationWalletOpener()),
                metadata: config.metadata,
                callbackURL: config.callbackURL
            )
        } catch {
            self.connector = WalletConnectDAppConnector(
                transport: UnavailableWalletTransportClient(message: error.localizedDescription),
                metadata: WalletConnectionMetadata(
                    appName: "AuraPlay",
                    appDescription: "NFT media player",
                    appURL: URL(string: "https://auraplay.app")!
                )
            )
            self.phase = .failed(error.localizedDescription)
        }

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
    func publish(_ request: WalletRequest, topic: WalletPairingTopic) async throws {
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
