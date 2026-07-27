import ReceiptsCore
import AccountStorage
import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import Foundation
import Security
import SwiftData
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters

@MainActor
/// Persists active wallet selection as protected, device-bound wallet metadata.
struct KeychainShellSelectionPersistence: ShellSelectionPersisting {
    private let store: KeychainShellSelectionStore
    private let defaultSelection = KeychainShellSelectionStore.SelectionRecord(
        address: "",
        chainID: Chain.ethMainnet.rawValue
    )

    init(service: String = "auralis.shell.selection.v1") {
        self.store = KeychainShellSelectionStore(service: service)
    }

    func loadSelection() async throws -> (address: String, chainID: String) {
        guard let selection = try await store.loadSelection() else {
            return (address: defaultSelection.address, chainID: defaultSelection.chainID)
        }

        return (address: selection.address, chainID: selection.chainID)
    }

    func saveSelection(address: String, chainID: String) async throws {
        try await store.saveSelection(
            KeychainShellSelectionStore.SelectionRecord(
                address: address,
                chainID: chainID
            )
        )
    }

    func clearSelection() async throws {
        try await store.clearSelection()
    }
}

enum ShellSelectionPersistenceError: LocalizedError, Equatable {
    case operationFailed(operation: String, status: OSStatus)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .operationFailed(let operation, let status):
            return "Auralis could not \(operation) the saved wallet selection. Keychain returned status \(status)."
        case .encodingFailed:
            return "Auralis could not encode the saved wallet selection."
        case .decodingFailed:
            return "Auralis could not decode the saved wallet selection."
        }
    }
}

actor KeychainShellSelectionStore {
    struct SelectionRecord: Codable, Equatable, Sendable {
        let address: String
        let chainID: String
    }

    private let service: String
    private let account = "active-selection"
    /// Active wallet selection may be read by shell restoration and refresh work after
    /// the first unlock, but it must not migrate through backup or device transfer.
    private let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    init(service: String) {
        self.service = service
    }

    func loadSelection() throws -> SelectionRecord? {
        var result: AnyObject?
        let status = SecItemCopyMatching(loadQuery as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let selection = try? JSONDecoder().decode(SelectionRecord.self, from: data) else {
                throw ShellSelectionPersistenceError.decodingFailed
            }

            return selection
        case errSecItemNotFound:
            return nil
        default:
            throw ShellSelectionPersistenceError.operationFailed(operation: "load", status: status)
        }
    }

    func saveSelection(_ selection: SelectionRecord) throws {
        guard let data = try? JSONEncoder().encode(selection) else {
            throw ShellSelectionPersistenceError.encodingFailed
        }

        let addStatus = SecItemAdd(addQuery(data: data) as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: accessibility
                ] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw ShellSelectionPersistenceError.operationFailed(operation: "update", status: updateStatus)
            }
        default:
            throw ShellSelectionPersistenceError.operationFailed(operation: "save", status: addStatus)
        }
    }

    func clearSelection() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw ShellSelectionPersistenceError.operationFailed(operation: "clear", status: status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    private var loadQuery: [String: Any] {
        baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ], uniquingKeysWith: { _, new in new })
    }

    private func addQuery(data: Data) -> [String: Any] {
        baseQuery.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ], uniquingKeysWith: { _, new in new })
    }
}

@MainActor
/// Resolves accounts from the SwiftData-backed account store.
struct SwiftDataShellAccountResolver: ShellAccountResolving {
    private let modelContext: ModelContext

    /// Creates a SwiftData account resolver for the supplied model context.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func account(for address: String) throws -> EOAccount? {
        try SwiftDataAccountStore(modelContext: modelContext).account(for: address)
    }

    func fallbackAccount() throws -> EOAccount? {
        try SwiftDataAccountStore(modelContext: modelContext).listAccounts().first
    }
}

@MainActor
/// Applies shell account mutations through the SwiftData-backed account store.
struct SwiftDataShellAccountMutator: ShellAccountMutating {
    private let modelContext: ModelContext
    private let eventRecorder: any AccountEventRecorder

    /// Creates a SwiftData account mutator and receipt-aware event recorder wrapper.
    init(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder
    ) {
        self.modelContext = modelContext
        self.eventRecorder = eventRecorder
    }

    func selectAccount(address: String, correlationID: String?) async throws -> EOAccount {
        try await SwiftDataAccountStore(
            modelContext: modelContext,
            eventRecorder: eventRecorder
        )
        .selectAccount(address: address, correlationID: correlationID)
    }

    func removeAccount(
        address: String,
        activeAddress: String,
        correlationID: String?
    ) async throws -> AccountRemovalResult {
        try await SwiftDataAccountStore(
            modelContext: modelContext,
            eventRecorder: eventRecorder
        )
        .removeAccount(
            address: address,
            activeAddress: activeAddress,
            correlationID: correlationID
        )
    }

    func persistCurrentChain(
        address: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount {
        let store = SwiftDataAccountStore(
            modelContext: modelContext,
            eventRecorder: eventRecorder
        )
        guard let account = try store.account(for: address) else {
            throw AccountStoreError.accountNotFound(address)
        }

        return try await store.persistCurrentChain(
            address: account.address,
            chain: chain,
            correlationID: correlationID
        )
    }
}

@MainActor
/// Bridges shell refresh requests to the shared NFT service.
struct NFTServiceShellRefreshCoordinator: ShellRefreshing {
    private let modelContext: ModelContext
    private let nftService: NFTService
    private let accountResolver: any ShellAccountResolving

    /// Creates a refresh coordinator backed by the shared NFT service and account resolver.
    init(
        modelContext: ModelContext,
        nftService: NFTService,
        accountResolver: any ShellAccountResolving
    ) {
        self.modelContext = modelContext
        self.nftService = nftService
        self.accountResolver = accountResolver
    }

    var isLoading: Bool {
        nftService.isLoading
    }

    var refreshTTL: TimeInterval {
        nftService.refreshTTL
    }

    func lastSuccessfulRefreshAt(for address: String, chain: Chain) -> Date? {
        nftService.lastSuccessfulRefreshAt(for: address, chain: chain)
    }

    func refresh(selection: ActiveShellSelection, correlationID: String?) async {
        let account = try? accountResolver.account(for: selection.address)
        await nftService.refreshNFTs(
            for: account,
            chain: selection.chain,
            modelContext: modelContext,
            correlationID: correlationID ?? UUID().uuidString
        )
    }
}

@MainActor
/// Records shell receipt events through the shared receipt event logger.
struct ReceiptEventShellLogger: ShellReceiptLogging {
    private let receiptEventLogger: ReceiptEventLogger

    /// Creates a shell receipt logger from the shared receipt event logger.
    init(receiptEventLogger: ReceiptEventLogger) {
        self.receiptEventLogger = receiptEventLogger
    }

    func recordAppLaunch(address: String, chain: Chain, correlationID: String) async {
        _ = try? await receiptEventLogger.recordAppLaunch(
            accountAddress: address,
            chain: chain,
            correlationID: correlationID
        )
    }
}

@MainActor
/// Applies shell routing effects to the shared app router.
struct AppRouterShellEffectHandler: ShellRouterEffectHandling {
    private let router: AppRouter
    private let modelContext: ModelContext

    /// Creates a router effect handler backed by the app router and model context.
    init(router: AppRouter, modelContext: ModelContext) {
        self.router = router
        self.modelContext = modelContext
    }

    func handle(_ effect: ShellRoutingEffect) -> AppRouteError? {
        switch effect {
        case .resetAllRoutes:
            router.resetAllPaths()
            return nil

        case .selectTab(let tab):
            router.selectedTab = tab
            return nil

        case .routeDeepLink(let destination, let selection, let inheritedChain):
            switch destination {
            case .nft(let id):
                do {
                    let normalizedAccountAddress = NFT.normalizedScopeComponent(selection.address) ?? ""
                    let chainRawValue = selection.chain.rawValue
                    let descriptor = FetchDescriptor<NFT>(
                        predicate: #Predicate<NFT> {
                            $0.id == id &&
                            $0.accountAddressRawValue == normalizedAccountAddress &&
                            $0.networkRawValue == chainRawValue
                        }
                    )
                    guard let nft = try modelContext.fetch(descriptor).first else {
                        return AppRouteError(
                            title: "NFT Not Found",
                            message: "The requested NFT could not be resolved for the current account.",
                            urlString: nil
                        )
                    }

                    router.showNFTFromHome(nft)
                    return nil
                } catch {
                    return AppRouteError(
                        title: "NFT Lookup Failed",
                        message: "Auralis could not resolve the requested NFT.",
                        urlString: nil
                    )
                }

            case .token(let contractAddress, let chain, let symbol):
                router.showERC20Token(
                    contractAddress: contractAddress,
                    chain: chain ?? inheritedChain ?? selection.chain,
                    symbol: symbol
                )
                return nil

            case .receipt(let id):
                router.showReceipt(id: id)
                return nil

            case .auraPlayPlaylist(let id):
                router.showMusicPlaylist(id: id)
                return nil

            case .auraPlayCollection(let identifier, let chain):
                let resolvedChain = chain ?? inheritedChain ?? selection.chain
                // Guard against an already-qualified `"chain|identifier"` value so
                // a composite id is not double-prefixed into `"chain|chain|id"`.
                let key = identifier.contains("|")
                    ? identifier
                    : "\(resolvedChain.rawValue)|\(identifier)"
                router.showMusicCollectionDetail(
                    key: key,
                    title: "Collection"
                )
                return nil

            case .auraPlayCreator(let identifier):
                router.showMusicCreator(id: identifier)
                return nil
            }
        }
    }
}
