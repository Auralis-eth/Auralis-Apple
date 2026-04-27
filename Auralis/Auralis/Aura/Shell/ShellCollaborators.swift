import Foundation
import SwiftData

@MainActor
/// Persists and restores the active shell wallet selection.
protocol ShellSelectionPersisting {
    func loadSelection() -> (address: String, chainID: String)
    func saveSelection(address: String, chainID: String)
    func clearSelection()
}

@MainActor
/// Resolves persisted accounts needed to restore or repair shell selection.
protocol ShellAccountResolving {
    func account(for address: String) throws -> EOAccount?
    func fallbackAccount() throws -> EOAccount?
}

@MainActor
/// Applies account mutations that change the shell's active wallet or chain.
protocol ShellAccountMutating {
    func selectAccount(address: String, correlationID: String?) async throws -> EOAccount
    func removeAccount(address: String, activeAddress: String, correlationID: String?) async throws -> AccountRemovalResult
    func persistCurrentChain(address: String, chain: Chain, correlationID: String?) async throws -> EOAccount
}

@MainActor
/// Refreshes data for the active shell selection and exposes refresh freshness.
protocol ShellRefreshing {
    var isLoading: Bool { get }
    var refreshTTL: TimeInterval { get }
    func lastSuccessfulRefreshAt(for address: String, chain: Chain) -> Date?
    func refresh(selection: ActiveShellSelection, correlationID: String?) async
}

/// Resolves pending deep links into shell actions once enough context is available.
protocol ShellDeepLinkReplaying {
    func resolve(deepLink: AppDeepLink, context: PendingDeepLinkContext) -> PendingDeepLinkResolution
}

@MainActor
/// Applies routing side effects emitted by the shell state machine.
protocol ShellRouterEffectHandling {
    func handle(_ effect: ShellRoutingEffect) -> AppRouteError?
}

@MainActor
/// Records receipt events emitted by shell-level actions.
protocol ShellReceiptLogging {
    func recordAppLaunch(address: String, chain: Chain, correlationID: String) async
}

/// Supplies the current time for refresh staleness decisions.
protocol ShellClock {
    var now: Date { get }
}

@MainActor
/// Persists the active shell selection in user defaults.
struct UserDefaultsShellSelectionPersistence: ShellSelectionPersisting {
    private let defaults: UserDefaults
    private let addressKey = "currentAccountAddress"
    private let chainIDKey = "currentChainId"

    /// Creates a user-defaults-backed selection persistence service.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSelection() -> (address: String, chainID: String) {
        (
            address: defaults.string(forKey: addressKey) ?? "",
            chainID: defaults.string(forKey: chainIDKey) ?? Chain.ethMainnet.rawValue
        )
    }

    func saveSelection(address: String, chainID: String) {
        defaults.set(address, forKey: addressKey)
        defaults.set(chainID, forKey: chainIDKey)
    }

    func clearSelection() {
        defaults.set("", forKey: addressKey)
        defaults.set(Chain.ethMainnet.rawValue, forKey: chainIDKey)
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
        try AccountStore(modelContext: modelContext).account(for: address)
    }

    func fallbackAccount() throws -> EOAccount? {
        try AccountStore(modelContext: modelContext).listAccounts().first
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
        try await AccountStore(
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
        try await AccountStore(
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
        let store = AccountStore(
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

/// Replays pending deep links using the shared deep-link resolver.
struct DefaultShellDeepLinkReplayer: ShellDeepLinkReplaying {
    private let resolver = PendingDeepLinkResolver()

    func resolve(deepLink: AppDeepLink, context: PendingDeepLinkContext) -> PendingDeepLinkResolution {
        resolver.resolve(deepLink, context: context)
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

/// Supplies wall-clock time from the current system clock.
struct SystemShellClock: ShellClock {
    var now: Date {
        Date()
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
            }
        }
    }
}
