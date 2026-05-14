import AccountsCore
import AuralisPrimaryModels
import Foundation

@MainActor
/// Persists and restores the active shell wallet selection.
public protocol ShellSelectionPersisting {
    func loadSelection() -> (address: String, chainID: String)
    func saveSelection(address: String, chainID: String)
    func clearSelection()
}

@MainActor
/// Resolves persisted accounts needed to restore or repair shell selection.
public protocol ShellAccountResolving {
    func account(for address: String) throws -> EOAccount?
    func fallbackAccount() throws -> EOAccount?
}

@MainActor
/// Applies account mutations that change the shell's active wallet or chain.
public protocol ShellAccountMutating {
    func selectAccount(address: String, correlationID: String?) async throws -> EOAccount
    func removeAccount(address: String, activeAddress: String, correlationID: String?) async throws -> AccountRemovalResult
    func persistCurrentChain(address: String, chain: Chain, correlationID: String?) async throws -> EOAccount
}

@MainActor
/// Refreshes data for the active shell selection and exposes refresh freshness.
public protocol ShellRefreshing {
    var isLoading: Bool { get }
    var refreshTTL: TimeInterval { get }
    func lastSuccessfulRefreshAt(for address: String, chain: Chain) -> Date?
    func refresh(selection: ActiveShellSelection, correlationID: String?) async
}

/// Resolves pending deep links into shell actions once enough context is available.
public protocol ShellDeepLinkReplaying {
    func resolve(deepLink: AppDeepLink, context: PendingDeepLinkContext) -> PendingDeepLinkResolution
}

@MainActor
/// Applies routing side effects emitted by the shell state machine.
public protocol ShellRouterEffectHandling {
    func handle(_ effect: ShellRoutingEffect) -> AppRouteError?
}

@MainActor
/// Records receipt events emitted by shell-level actions.
public protocol ShellReceiptLogging {
    func recordAppLaunch(address: String, chain: Chain, correlationID: String) async
}

/// Supplies the current time for refresh staleness decisions.
public protocol ShellClock {
    var now: Date { get }
}

@MainActor
/// Bundles the explicit collaborators required by the shell reducer.
public struct ShellStoreDependencies {
    public let selectionPersistence: any ShellSelectionPersisting
    public let accountResolver: any ShellAccountResolving
    public let accountMutator: any ShellAccountMutating
    public let refreshCoordinator: any ShellRefreshing
    public let deepLinkReplayer: any ShellDeepLinkReplaying
    public let routerEffectHandler: any ShellRouterEffectHandling
    public let receiptLogger: any ShellReceiptLogging
    public let clock: any ShellClock

    public init(
        selectionPersistence: any ShellSelectionPersisting,
        accountResolver: any ShellAccountResolving,
        accountMutator: any ShellAccountMutating,
        refreshCoordinator: any ShellRefreshing,
        deepLinkReplayer: any ShellDeepLinkReplaying,
        routerEffectHandler: any ShellRouterEffectHandling,
        receiptLogger: any ShellReceiptLogging,
        clock: any ShellClock
    ) {
        self.selectionPersistence = selectionPersistence
        self.accountResolver = accountResolver
        self.accountMutator = accountMutator
        self.refreshCoordinator = refreshCoordinator
        self.deepLinkReplayer = deepLinkReplayer
        self.routerEffectHandler = routerEffectHandler
        self.receiptLogger = receiptLogger
        self.clock = clock
    }
}

/// Replays pending deep links using the shared deep-link resolver.
public struct DefaultShellDeepLinkReplayer: ShellDeepLinkReplaying {
    private let resolver = PendingDeepLinkResolver()

    public init() { }

    public func resolve(deepLink: AppDeepLink, context: PendingDeepLinkContext) -> PendingDeepLinkResolution {
        resolver.resolve(deepLink, context: context)
    }
}

/// Supplies wall-clock time from the current system clock.
public struct SystemShellClock: ShellClock {
    public init() { }

    public var now: Date {
        Date()
    }
}
