import Foundation
import SwiftData

@MainActor
protocol ShellSelectionPersisting {
    func loadSelection() -> (address: String, chainID: String)
    func saveSelection(address: String, chainID: String)
    func clearSelection()
}

@MainActor
protocol ShellAccountResolving {
    func account(for address: String) throws -> EOAccount?
    func fallbackAccount() throws -> EOAccount?
}

@MainActor
protocol ShellAccountMutating {
    func selectAccount(address: String, correlationID: String?) throws -> EOAccount
    func removeAccount(address: String, activeAddress: String, correlationID: String?) throws -> AccountRemovalResult
    func persistCurrentChain(address: String, chain: Chain, correlationID: String?) throws -> EOAccount
}

@MainActor
protocol ShellRefreshing {
    var isLoading: Bool { get }
    var refreshTTL: TimeInterval { get }
    func lastSuccessfulRefreshAt(for address: String, chain: Chain) -> Date?
    func refresh(selection: ActiveShellSelection, correlationID: String?) async
}

protocol ShellDeepLinkReplaying {
    func resolve(deepLink: AppDeepLink, context: PendingDeepLinkContext) -> PendingDeepLinkResolution
}

@MainActor
protocol ShellRouterEffectHandling {
    func handle(_ effect: ShellRoutingEffect) -> AppRouteError?
}

@MainActor
protocol ShellReceiptLogging {
    func recordAppLaunch(address: String, chain: Chain, correlationID: String)
}

protocol ShellClock {
    var now: Date { get }
}

@MainActor
struct UserDefaultsShellSelectionPersistence: ShellSelectionPersisting {
    private let defaults: UserDefaults
    private let addressKey = "currentAccountAddress"
    private let chainIDKey = "currentChainId"

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
struct SwiftDataShellAccountResolver: ShellAccountResolving {
    private let modelContext: ModelContext

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
struct SwiftDataShellAccountMutator: ShellAccountMutating {
    private let modelContext: ModelContext
    private let eventRecorder: any AccountEventRecorder

    init(
        modelContext: ModelContext,
        eventRecorder: any AccountEventRecorder
    ) {
        self.modelContext = modelContext
        self.eventRecorder = eventRecorder
    }

    func selectAccount(address: String, correlationID: String?) throws -> EOAccount {
        try AccountStore(
            modelContext: modelContext,
            eventRecorder: eventRecorder
        )
        .selectAccount(address: address, correlationID: correlationID)
    }

    func removeAccount(
        address: String,
        activeAddress: String,
        correlationID: String?
    ) throws -> AccountRemovalResult {
        try AccountStore(
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
    ) throws -> EOAccount {
        let store = AccountStore(
            modelContext: modelContext,
            eventRecorder: eventRecorder
        )
        guard let account = try store.account(for: address) else {
            throw AccountStoreError.accountNotFound(address)
        }

        let previousChain = account.currentChain
        guard previousChain != chain else {
            return account
        }

        account.currentChain = chain

        do {
            try modelContext.save()
            eventRecorder.record(
                .currentChainChanged(address: account.address, from: previousChain, to: chain),
                correlationID: correlationID
            )
            return account
        } catch {
            account.currentChain = previousChain
            throw error
        }
    }
}

@MainActor
struct NFTServiceShellRefreshCoordinator: ShellRefreshing {
    private let modelContext: ModelContext
    private let nftService: NFTService
    private let accountResolver: any ShellAccountResolving

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

struct DefaultShellDeepLinkReplayer: ShellDeepLinkReplaying {
    private let resolver = PendingDeepLinkResolver()

    func resolve(deepLink: AppDeepLink, context: PendingDeepLinkContext) -> PendingDeepLinkResolution {
        resolver.resolve(deepLink, context: context)
    }
}

@MainActor
struct ReceiptEventShellLogger: ShellReceiptLogging {
    private let receiptEventLogger: ReceiptEventLogger

    init(receiptEventLogger: ReceiptEventLogger) {
        self.receiptEventLogger = receiptEventLogger
    }

    func recordAppLaunch(address: String, chain: Chain, correlationID: String) {
        receiptEventLogger.recordAppLaunch(
            accountAddress: address,
            chain: chain,
            correlationID: correlationID
        )
    }
}

struct SystemShellClock: ShellClock {
    var now: Date {
        Date()
    }
}

@MainActor
struct AppRouterShellEffectHandler: ShellRouterEffectHandling {
    private let router: AppRouter
    private let modelContext: ModelContext

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
