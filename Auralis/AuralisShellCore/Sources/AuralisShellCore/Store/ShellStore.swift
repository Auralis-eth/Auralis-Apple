import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import Observation

@MainActor
@Observable
/// Coordinates shell state transitions, persistence restore, refreshes, and deep-link replay.
public final class ShellStore {
    public private(set) var state: ShellState

    private let selectionPersistence: any ShellSelectionPersisting
    private let accountResolver: any ShellAccountResolving
    private let accountMutator: any ShellAccountMutating
    private let refreshCoordinator: any ShellRefreshing
    private let deepLinkReplayer: any ShellDeepLinkReplaying
    private let routerEffectHandler: any ShellRouterEffectHandling
    private let receiptLogger: any ShellReceiptLogging
    private let clock: any ShellClock

    private var refreshTask: Task<Void, Never>?
    private var didRecordAppLaunchReceipt = false

    /// Creates a shell store with explicit collaborators for persistence, routing, and refresh work.
    public init(
        state: ShellState = ShellState(),
        selectionPersistence: any ShellSelectionPersisting,
        accountResolver: any ShellAccountResolving,
        accountMutator: any ShellAccountMutating,
        refreshCoordinator: any ShellRefreshing,
        deepLinkReplayer: any ShellDeepLinkReplaying,
        routerEffectHandler: any ShellRouterEffectHandling,
        receiptLogger: any ShellReceiptLogging,
        clock: any ShellClock
    ) {
        self.state = state
        self.selectionPersistence = selectionPersistence
        self.accountResolver = accountResolver
        self.accountMutator = accountMutator
        self.refreshCoordinator = refreshCoordinator
        self.deepLinkReplayer = deepLinkReplayer
        self.routerEffectHandler = routerEffectHandler
        self.receiptLogger = receiptLogger
        self.clock = clock
    }

    /// Builds the production shell store wired to live services and the app router.
    public static func live(
        dependencies: ShellStoreDependencies
    ) -> ShellStore {
        return ShellStore(
            selectionPersistence: dependencies.selectionPersistence,
            accountResolver: dependencies.accountResolver,
            accountMutator: dependencies.accountMutator,
            refreshCoordinator: dependencies.refreshCoordinator,
            deepLinkReplayer: dependencies.deepLinkReplayer,
            routerEffectHandler: dependencies.routerEffectHandler,
            receiptLogger: dependencies.receiptLogger,
            clock: dependencies.clock
        )
    }

    /// Builds a preview shell store with inert collaborators and optional seeded selection.
    public static func preview(selection: ActiveShellSelection? = nil) -> ShellStore {
        ShellStore(
            state: ShellState(selection: selection),
            selectionPersistence: PreviewShellSelectionPersistence(),
            accountResolver: PreviewShellAccountResolver(),
            accountMutator: PreviewShellAccountMutator(),
            refreshCoordinator: PreviewShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: PreviewShellRouterEffectHandler(),
            receiptLogger: PreviewShellReceiptLogger(),
            clock: SystemShellClock()
        )
    }

    /// Applies a shell action and updates state, routing, or refresh work as needed.
    public func send(_ action: ShellAction) async {
        switch action {
        case .restoreFromPersistence:
            await restoreFromPersistence()
            await send(.attemptPendingDeepLinkReplay)

        case .accountActivated(let account, let correlationID):
            await commitSelection(
                account: account,
                chain: account.currentChain,
                correlationID: correlationID,
                resetsRoutes: false,
                refreshesSelection: true
            )

        case .accountSelectionRequested(let address, let correlationID, let chainOverride):
            do {
                let account = try await accountMutator.selectAccount(
                    address: address,
                    correlationID: correlationID
                )
                await commitSelection(
                    account: account,
                    chain: chainOverride ?? account.currentChain,
                    correlationID: correlationID,
                    resetsRoutes: state.selection?.address != account.address,
                    refreshesSelection: state.selection?.address != account.address || state.selection?.chain != (chainOverride ?? account.currentChain)
                )
            } catch {
                state.routeError = AppRouteError(
                    title: "Selection Failed",
                    message: error.localizedDescription,
                    urlString: nil
                )
            }

        case .activeAccountRemovalRequested(let address, let correlationID):
            await removeActiveAccount(address: address, correlationID: correlationID)

        case .chainChangeRequested(let chain, let correlationID):
            await applyChainChange(chain, correlationID: correlationID)

        case .refreshCurrentSelectionRequested(let correlationID):
            guard let selection = state.selection else {
                return
            }
            startRefresh(for: selection, correlationID: correlationID)

        case .refreshStarted(let requestID, let selection, let correlationID):
            beginRefresh(
                requestID: requestID,
                selection: selection,
                correlationID: correlationID
            )

        case .refreshFinished(let requestID, let selection):
            guard state.latestRefreshRequestID == requestID else {
                return
            }
            state.latestRefreshRequestID = nil
            state.isRefreshingSelection = false
            refreshTask = nil
            state.selection = selection
            updateAuthenticatedPresentationState()
            await send(.attemptPendingDeepLinkReplay)

        case .deepLinkReceived(let deepLink):
            state.pendingDeepLink = deepLink
            await send(.attemptPendingDeepLinkReplay)

        case .attemptPendingDeepLinkReplay:
            await replayPendingDeepLinkIfPossible()

        case .routeErrorEncountered(let routeError):
            state.routeError = routeError

        case .routeErrorDismissed:
            state.routeError = nil

        case .sceneBecameActive:
            await refreshActiveSelectionIfStaleAfterForeground()

        case .logoutRequested:
            await performLogout()

        case .pendingCorrelationConsumed(let correlationID):
            guard state.pendingCorrelationID == correlationID else {
                return
            }
            state.pendingCorrelationID = nil
        }
    }

    private func restoreFromPersistence() async {
        do {
            let persistedSelection = try await selectionPersistence.loadSelection()
            let persistedAccount = try? accountResolver.account(for: persistedSelection.address)
            let fallbackAccount = persistedAccount == nil ? (try? accountResolver.fallbackAccount()) : nil
            let activeAccount = persistedAccount ?? fallbackAccount

            if let activeAccount {
                let restoredChain = restoredChain(
                    persistedChainRawValue: persistedSelection.chainID,
                    account: activeAccount
                )
                let selection = ActiveShellSelection(
                    address: activeAccount.address,
                    chain: restoredChain
                )
                applyCommittedSelection(selection, account: activeAccount)
                try await persistSelection(selection)
            } else if persistedSelection.address.isEmpty {
                state.selection = nil
                state.activeAccountID = nil
                try await selectionPersistence.clearSelection()
            } else {
                state.selection = nil
                state.activeAccountID = nil
                try await selectionPersistence.clearSelection()
            }
        } catch {
            state.selection = nil
            state.activeAccountID = nil
            state.routeError = persistenceRouteError(
                title: "Wallet Restore Failed",
                fallbackMessage: "Auralis could not read the saved wallet selection on this device.",
                error: error
            )
        }

        state.didFinishInitialRestore = true
        updateAuthenticatedPresentationState()
        await recordAppLaunchIfNeeded()
    }

    private func removeActiveAccount(address: String, correlationID: String?) async {
        do {
            let activeAddress = state.selection?.address ?? ""
            let result = try await accountMutator.removeAccount(
                address: address,
                activeAddress: activeAddress,
                correlationID: correlationID
            )

            guard activeAddress == result.removedAddress else {
                return
            }

            applyRoutingEffect(.resetAllRoutes)
            applyRoutingEffect(.selectTab(.home))

            if let fallbackAccount = result.fallbackAccount {
                let selection = ActiveShellSelection(
                    address: fallbackAccount.address,
                    chain: fallbackAccount.currentChain
                )
                applyCommittedSelection(selection, account: fallbackAccount)
                try await persistSelection(selection)
            } else {
                state.selection = nil
                state.activeAccountID = nil
                state.pendingCorrelationID = nil
                state.pendingDeepLink = nil
                state.hasPresentedAuthenticatedExperience = false
                try await selectionPersistence.clearSelection()
            }
        } catch {
            state.routeError = AppRouteError(
                title: "Removal Failed",
                message: error.localizedDescription,
                urlString: nil
            )
        }
    }

    private func applyChainChange(_ chain: Chain, correlationID: String?) async {
        guard let selection = state.selection else {
            return
        }

        guard selection.chain != chain else {
            return
        }

        do {
            let account = try await accountMutator.persistCurrentChain(
                address: selection.address,
                chain: chain,
                correlationID: correlationID
            )
            let nextSelection = ActiveShellSelection(
                address: selection.address,
                chain: chain
            )
            applyCommittedSelection(nextSelection, account: account)
            try await persistSelection(nextSelection)
            startRefresh(for: nextSelection, correlationID: correlationID)
        } catch {
            state.routeError = AppRouteError(
                title: "Chain Change Failed",
                message: "Auralis could not save the selected chain. Your previous chain is still active.",
                urlString: nil
            )
        }
    }

    private func commitSelection(
        account: EOAccount,
        chain: Chain,
        correlationID: String?,
        resetsRoutes: Bool,
        refreshesSelection: Bool
    ) async {
        let nextSelection = ActiveShellSelection(
            address: account.address,
            chain: chain
        )
        let previousSelection = state.selection

        if resetsRoutes {
            applyRoutingEffect(.resetAllRoutes)
        }

        applyCommittedSelection(nextSelection, account: account)
        do {
            try await persistSelection(nextSelection)
        } catch {
            state.routeError = persistenceRouteError(
                title: "Selection Persistence Failed",
                fallbackMessage: "Auralis selected the wallet but could not save that selection for the next launch.",
                error: error
            )
            return
        }

        if refreshesSelection {
            startRefresh(for: nextSelection, correlationID: correlationID)
        } else if previousSelection != nextSelection {
            updateAuthenticatedPresentationState()
            await send(.attemptPendingDeepLinkReplay)
        }
    }

    private func applyCommittedSelection(_ selection: ActiveShellSelection, account: EOAccount) {
        state.selection = selection
        state.activeAccountID = account.address
        state.pendingCorrelationID = nil
    }

    private func startRefresh(for selection: ActiveShellSelection, correlationID: String?) {
        beginRefresh(
            requestID: UUID(),
            selection: selection,
            correlationID: correlationID ?? UUID().uuidString
        )
    }

    private func beginRefresh(
        requestID: UUID,
        selection: ActiveShellSelection,
        correlationID: String?
    ) {
        state.latestRefreshRequestID = requestID
        state.isRefreshingSelection = true
        state.pendingCorrelationID = correlationID
        state.selection = selection
        refreshTask?.cancel()
        let refreshCoordinator = refreshCoordinator
        refreshTask = Task { [weak self] in
            await refreshCoordinator.refresh(
                selection: selection,
                correlationID: correlationID
            )
            await self?.send(
                .refreshFinished(
                    requestID: requestID,
                    selection: selection
                )
            )
        }
    }

    private func replayPendingDeepLinkIfPossible() async {
        guard let pendingDeepLink = state.pendingDeepLink else {
            return
        }

        let currentAccountAddress = activeAccountAddress
        let resolution = deepLinkReplayer.resolve(
            deepLink: pendingDeepLink,
            context: PendingDeepLinkContext(
                currentAddress: state.selection?.address ?? "",
                currentAccountAddress: currentAccountAddress,
                canResolveDeferredLink: canResolveDeferredLink,
                shouldFailDeferredLink: shouldFailDeferredLink
            )
        )

        switch resolution.action {
        case .wait:
            return

        case .switchAccount(let address):
            applyRoutingEffect(.resetAllRoutes)
            applyRoutingEffect(.selectTab(.home))
            await send(
                .accountSelectionRequested(
                    address: address,
                    correlationID: state.pendingCorrelationID,
                    chainOverride: resolution.chainOverride
                )
            )

        case .showHome:
            if let chainOverride = resolution.chainOverride {
                await applyChainChange(chainOverride, correlationID: state.pendingCorrelationID)
            }
            applyRoutingEffect(.resetAllRoutes)
            applyRoutingEffect(.selectTab(.home))
            state.pendingDeepLink = nil

        case .route(let destination, let inheritedChain):
            if let chainOverride = resolution.chainOverride,
               state.selection?.chain != chainOverride {
                await applyChainChange(chainOverride, correlationID: state.pendingCorrelationID)
            }

            guard let selection = state.selection else {
                return
            }

            if let routeError = applyRoutingEffect(
                .routeDeepLink(
                    destination: destination,
                    selection: selection,
                    inheritedChain: inheritedChain
                )
            ) {
                state.routeError = routeError
            }
            state.pendingDeepLink = nil

        case .showError(let routeError):
            state.routeError = routeError
            state.pendingDeepLink = nil
        }
    }

    private func refreshActiveSelectionIfStaleAfterForeground() async {
        guard let selection = state.selection else {
            return
        }

        guard !state.isRefreshingSelection, !refreshCoordinator.isLoading else {
            return
        }

        let isStale: Bool
        if let lastSuccessfulRefreshAt = refreshCoordinator.lastSuccessfulRefreshAt(
            for: selection.address,
            chain: selection.chain
        ) {
            isStale = clock.now.timeIntervalSince(lastSuccessfulRefreshAt) >= refreshCoordinator.refreshTTL
        } else {
            isStale = true
        }

        guard isStale else {
            return
        }

        startRefresh(for: selection, correlationID: UUID().uuidString)
    }

    private func performLogout() async {
        refreshTask?.cancel()
        refreshTask = nil
        state = ShellState(
            selection: nil,
            activeAccountID: nil,
            pendingDeepLink: nil,
            pendingCorrelationID: nil,
            latestRefreshRequestID: nil,
            isRefreshingSelection: false,
            hasPresentedAuthenticatedExperience: false,
            didFinishInitialRestore: true,
            routeError: nil
        )
        do {
            try await selectionPersistence.clearSelection()
        } catch {
            state.routeError = persistenceRouteError(
                title: "Logout Persistence Failed",
                fallbackMessage: "Auralis logged out but could not clear the saved wallet selection.",
                error: error
            )
        }
        applyRoutingEffect(.resetAllRoutes)
        applyRoutingEffect(.selectTab(.home))
    }

    private var activeAccountAddress: String? {
        state.selection?.address
    }

    private var canResolveDeferredLink: Bool {
        state.selection != nil && state.activeAccountID != nil && !state.isRefreshingSelection && !refreshCoordinator.isLoading
    }

    private var shouldFailDeferredLink: Bool {
        state.didFinishInitialRestore &&
            state.selection == nil &&
            !state.isRefreshingSelection &&
            !refreshCoordinator.isLoading
    }

    private func updateAuthenticatedPresentationState() {
        guard state.selection != nil, state.activeAccountID != nil, !state.isRefreshingSelection else {
            return
        }

        state.hasPresentedAuthenticatedExperience = true
    }

    private func recordAppLaunchIfNeeded() async {
        guard !didRecordAppLaunchReceipt else {
            return
        }

        let selection = state.selection ?? ActiveShellSelection(address: "", chain: .ethMainnet)
        await receiptLogger.recordAppLaunch(
            address: selection.address,
            chain: selection.chain,
            correlationID: UUID().uuidString
        )
        didRecordAppLaunchReceipt = true
    }

    @discardableResult
    private func applyRoutingEffect(_ effect: ShellRoutingEffect) -> AppRouteError? {
        routerEffectHandler.handle(effect)
    }

    private func persistSelection(_ selection: ActiveShellSelection) async throws {
        try await selectionPersistence.saveSelection(
            address: selection.address,
            chainID: selection.chain.rawValue
        )
    }

    private func persistenceRouteError(
        title: String,
        fallbackMessage: String,
        error: Error
    ) -> AppRouteError {
        AppRouteError(
            title: title,
            message: error.localizedDescription.isEmpty ? fallbackMessage : error.localizedDescription,
            urlString: nil
        )
    }

    private func restoredChain(
        persistedChainRawValue: String,
        account: EOAccount
    ) -> Chain {
        if let persistedChain = Chain.resolved(rawValue: persistedChainRawValue),
           persistedChain == account.currentChainOrNil || account.currentChainOrNil == nil {
            return persistedChain
        }

        if let currentChain = account.currentChainOrNil {
            return currentChain
        }

        if let preferredChain = account.preferredChainOrNil {
            return preferredChain
        }

        return .ethMainnet
    }
}

@MainActor
private struct PreviewShellSelectionPersistence: ShellSelectionPersisting {
    func loadSelection() async throws -> (address: String, chainID: String) {
        ("", Chain.ethMainnet.rawValue)
    }

    func saveSelection(address: String, chainID: String) async throws { }

    func clearSelection() async throws { }
}

@MainActor
private struct PreviewShellAccountResolver: ShellAccountResolving {
    func account(for address: String) throws -> EOAccount? {
        nil
    }

    func fallbackAccount() throws -> EOAccount? {
        nil
    }
}

@MainActor
private struct PreviewShellAccountMutator: ShellAccountMutating {
    func selectAccount(address: String, correlationID: String?) async throws -> EOAccount {
        EOAccount(address: address)
    }

    func removeAccount(address: String, activeAddress: String, correlationID: String?) async throws -> AccountRemovalResult {
        AccountRemovalResult(removedAddress: address, fallbackAccount: nil)
    }

    func persistCurrentChain(address: String, chain: Chain, correlationID: String?) async throws -> EOAccount {
        let account = EOAccount(address: address)
        account.currentChain = chain
        return account
    }
}

@MainActor
private struct PreviewShellRefreshCoordinator: ShellRefreshing {
    var isLoading: Bool {
        false
    }

    var refreshTTL: TimeInterval {
        60
    }

    func lastSuccessfulRefreshAt(for address: String, chain: Chain) -> Date? {
        nil
    }

    func refresh(selection: ActiveShellSelection, correlationID: String?) async { }
}

@MainActor
private struct PreviewShellRouterEffectHandler: ShellRouterEffectHandling {
    func handle(_ effect: ShellRoutingEffect) -> AppRouteError? {
        nil
    }
}

@MainActor
private struct PreviewShellReceiptLogger: ShellReceiptLogging {
    func recordAppLaunch(address: String, chain: Chain, correlationID: String) async { }
}
