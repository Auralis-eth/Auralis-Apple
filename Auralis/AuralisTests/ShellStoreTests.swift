@testable import Auralis
import AccountsCore
import AuralisPrimaryModels
import Foundation
import Testing

@Suite
struct ShellStoreTests {
    @Test("restore from persistence repairs chain mismatch from the account and records app launch once")
    @MainActor
    func restoreFromPersistenceRepairsChainMismatchAndRecordsAppLaunch() async {
        let account = makeAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            currentChain: .baseMainnet
        )
        let persistence = TestShellSelectionPersistence(
            loadedSelection: (account.address, Chain.ethMainnet.rawValue)
        )
        let receiptLogger = TestShellReceiptLogger()
        let store = makeStore(
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(accounts: [account.address: account]),
            receiptLogger: receiptLogger
        )

        await store.send(.restoreFromPersistence)
        await store.send(.restoreFromPersistence)

        #expect(store.state.selection == ActiveShellSelection(address: account.address, chain: .baseMainnet))
        #expect(store.state.activeAccountID == account.persistentModelID)
        #expect(store.state.didFinishInitialRestore)
        #expect(store.state.hasPresentedAuthenticatedExperience)
        #expect(persistence.savedSelections.map(\.chainID) == [Chain.baseMainnet.rawValue, Chain.baseMainnet.rawValue])
        #expect(receiptLogger.appLaunches.count == 1)
        #expect(receiptLogger.appLaunches.first?.address == account.address)
        #expect(receiptLogger.appLaunches.first?.chain == .baseMainnet)
    }

    @Test("restore from persistence falls back to the first available account when the saved one is gone")
    @MainActor
    func restoreFromPersistenceUsesFallbackAccount() async {
        let fallbackAccount = makeAccount(
            address: "0xfedcba0987654321fedcba0987654321fedcba09",
            currentChain: .polygonMainnet
        )
        let persistence = TestShellSelectionPersistence(
            loadedSelection: ("0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef", Chain.ethMainnet.rawValue)
        )
        let store = makeStore(
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(
                accounts: [:],
                fallbackAccount: fallbackAccount
            )
        )

        await store.send(.restoreFromPersistence)

        #expect(store.state.selection == ActiveShellSelection(address: fallbackAccount.address, chain: .polygonMainnet))
        #expect(store.state.activeAccountID == fallbackAccount.persistentModelID)
        #expect(persistence.savedSelections.last?.address == fallbackAccount.address)
        #expect(persistence.savedSelections.last?.chainID == Chain.polygonMainnet.rawValue)
    }

    @Test("account selection request resets routes and refreshes when switching to another account")
    @MainActor
    func accountSelectionRequestResetsRoutesAndRefreshesWhenAddressChanges() async {
        let previousAccount = makeAccount(
            address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            currentChain: .ethMainnet
        )
        let nextAccount = makeAccount(
            address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            currentChain: .baseMainnet
        )
        let mutator = TestShellAccountMutator(selectResult: .success(nextAccount))
        let refreshCoordinator = TestShellRefreshCoordinator()
        let router = TestShellRouterEffectHandler()
        let store = makeStore(
            state: ShellState(
                selection: ActiveShellSelection(address: previousAccount.address, chain: .ethMainnet),
                activeAccountID: previousAccount.persistentModelID
            ),
            selectionPersistence: TestShellSelectionPersistence(),
            accountMutator: mutator,
            refreshCoordinator: refreshCoordinator,
            routerEffectHandler: router
        )

        await store.send(
            .accountSelectionRequested(
                address: nextAccount.address,
                correlationID: "select-1",
                chainOverride: nil
            )
        )
        await settleAsyncWork()

        #expect(mutator.selectCalls.count == 1)
        #expect(mutator.selectCalls.first?.address == nextAccount.address)
        #expect(mutator.selectCalls.first?.correlationID == "select-1")
        #expect(router.effects == [.resetAllRoutes])
        #expect(store.state.selection == ActiveShellSelection(address: nextAccount.address, chain: .baseMainnet))
        #expect(store.state.hasPresentedAuthenticatedExperience)
        #expect(refreshCoordinator.refreshCalls == [
            TestShellRefreshCoordinator.RefreshCall(
                selection: ActiveShellSelection(address: nextAccount.address, chain: .baseMainnet),
                correlationID: "select-1"
            )
        ])
    }

    @Test("chain change persists the new chain and refreshes the active selection")
    @MainActor
    func chainChangePersistsAndRefreshes() async {
        let account = makeAccount(
            address: "0xcccccccccccccccccccccccccccccccccccccccc",
            currentChain: .polygonMainnet
        )
        let mutator = TestShellAccountMutator(persistChainResult: .success(account))
        let refreshCoordinator = TestShellRefreshCoordinator()
        let persistence = TestShellSelectionPersistence()
        let store = makeStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID
            ),
            selectionPersistence: persistence,
            accountMutator: mutator,
            refreshCoordinator: refreshCoordinator
        )

        await store.send(.chainChangeRequested(chain: .polygonMainnet, correlationID: "chain-1"))
        await settleAsyncWork()

        #expect(mutator.persistChainCalls.count == 1)
        #expect(mutator.persistChainCalls.first?.address == account.address)
        #expect(mutator.persistChainCalls.first?.chain == .polygonMainnet)
        #expect(mutator.persistChainCalls.first?.correlationID == "chain-1")
        #expect(store.state.selection == ActiveShellSelection(address: account.address, chain: .polygonMainnet))
        #expect(persistence.savedSelections.last?.chainID == Chain.polygonMainnet.rawValue)
        #expect(refreshCoordinator.refreshCalls == [
            TestShellRefreshCoordinator.RefreshCall(
                selection: ActiveShellSelection(address: account.address, chain: .polygonMainnet),
                correlationID: "chain-1"
            )
        ])
    }

    @Test("deep link replay routes immediately when the shell is ready")
    @MainActor
    func deepLinkReplayRoutesWhenReady() async {
        let account = makeAccount(
            address: "0xdddddddddddddddddddddddddddddddddddddddd",
            currentChain: .baseMainnet
        )
        let router = TestShellRouterEffectHandler()
        let replayer = TestShellDeepLinkReplayer(
            nextResolution: PendingDeepLinkResolution(
                chainOverride: nil,
                action: .route(
                    destination: .token(
                        contractAddress: "0xfeed",
                        chain: .baseMainnet,
                        symbol: "AURA"
                    ),
                    inheritedChain: .baseMainnet
                )
            )
        )
        let store = makeStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .baseMainnet),
                activeAccountID: account.persistentModelID,
                didFinishInitialRestore: true
            ),
            deepLinkReplayer: replayer,
            routerEffectHandler: router
        )

        await store.send(
            .deepLinkReceived(
                .destination(
                    .token(
                        contractAddress: "0xfeed",
                        chain: .baseMainnet,
                        symbol: "AURA"
                    )
                )
            )
        )

        #expect(store.state.pendingDeepLink == nil)
        #expect(router.effects == [
            .routeDeepLink(
                destination: .token(
                    contractAddress: "0xfeed",
                    chain: .baseMainnet,
                    symbol: "AURA"
                ),
                selection: ActiveShellSelection(address: account.address, chain: .baseMainnet),
                inheritedChain: .baseMainnet
            )
        ])
        #expect(replayer.resolvedContexts.count == 1)
        #expect(replayer.resolvedContexts.first?.canResolveDeferredLink == true)
    }

    @Test("deep link replay waits when dependencies are not ready yet")
    @MainActor
    func deepLinkReplayWaitsWhenNotReady() async {
        let replayer = TestShellDeepLinkReplayer(
            nextResolution: PendingDeepLinkResolution(
                chainOverride: nil,
                action: .wait
            )
        )
        let pendingLink = AppDeepLink.destination(.receipt(id: "receipt-1"))
        let store = makeStore(
            state: ShellState(
                selection: nil,
                activeAccountID: nil,
                didFinishInitialRestore: false
            ),
            deepLinkReplayer: replayer
        )

        await store.send(.deepLinkReceived(pendingLink))

        #expect(store.state.pendingDeepLink == pendingLink)
        #expect(replayer.resolvedContexts.count == 1)
        #expect(replayer.resolvedContexts.first?.canResolveDeferredLink == false)
        #expect(replayer.resolvedContexts.first?.shouldFailDeferredLink == false)
    }

    @Test("scene became active refreshes when the active selection is stale")
    @MainActor
    func sceneBecameActiveRefreshesWhenStale() async {
        let account = makeAccount(
            address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
            currentChain: .ethMainnet
        )
        let refreshCoordinator = TestShellRefreshCoordinator(
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 100)
        )
        let store = makeStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID,
                didFinishInitialRestore: true
            ),
            refreshCoordinator: refreshCoordinator,
            clock: TestShellClock(now: Date(timeIntervalSince1970: 200))
        )

        await store.send(.sceneBecameActive)
        await settleAsyncWork()

        #expect(refreshCoordinator.refreshCalls.count == 1)
        #expect(store.state.hasPresentedAuthenticatedExperience)
    }

    @Test("scene became active skips refresh when the active selection is still fresh")
    @MainActor
    func sceneBecameActiveSkipsRefreshWhenFresh() async {
        let account = makeAccount(
            address: "0xffffffffffffffffffffffffffffffffffffffff",
            currentChain: .ethMainnet
        )
        let refreshCoordinator = TestShellRefreshCoordinator(
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 170)
        )
        let store = makeStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID,
                didFinishInitialRestore: true
            ),
            refreshCoordinator: refreshCoordinator,
            clock: TestShellClock(now: Date(timeIntervalSince1970: 200))
        )

        await store.send(.sceneBecameActive)
        await settleAsyncWork()

        #expect(refreshCoordinator.refreshCalls.isEmpty)
        #expect(store.state.isRefreshingSelection == false)
    }

    @Test("logout clears shell state, clears persistence, and routes back home")
    @MainActor
    func logoutClearsStateAndRoutesHome() async {
        let account = makeAccount(
            address: "0x9999999999999999999999999999999999999999",
            currentChain: .baseMainnet
        )
        let persistence = TestShellSelectionPersistence()
        let router = TestShellRouterEffectHandler()
        let store = makeStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .baseMainnet),
                activeAccountID: account.persistentModelID,
                pendingDeepLink: .destination(.receipt(id: "logout")),
                pendingCorrelationID: "logout-1",
                latestRefreshRequestID: UUID(),
                isRefreshingSelection: true,
                hasPresentedAuthenticatedExperience: true,
                didFinishInitialRestore: true,
                routeError: AppRouteError(
                    title: "Old Error",
                    message: "Should be cleared",
                    urlString: nil
                )
            ),
            selectionPersistence: persistence,
            routerEffectHandler: router
        )

        await store.send(.logoutRequested)

        #expect(store.state.selection == nil)
        #expect(store.state.activeAccountID == nil)
        #expect(store.state.pendingDeepLink == nil)
        #expect(store.state.pendingCorrelationID == nil)
        #expect(store.state.latestRefreshRequestID == nil)
        #expect(store.state.isRefreshingSelection == false)
        #expect(store.state.hasPresentedAuthenticatedExperience == false)
        #expect(store.state.didFinishInitialRestore == true)
        #expect(store.state.routeError == nil)
        #expect(persistence.clearSelectionCallCount == 1)
        #expect(router.effects == [.resetAllRoutes, .selectTab(.home)])
    }

    @MainActor
    private func makeStore(
        state: ShellState = ShellState(),
        selectionPersistence: TestShellSelectionPersistence = TestShellSelectionPersistence(),
        accountResolver: TestShellAccountResolver = TestShellAccountResolver(),
        accountMutator: TestShellAccountMutator = TestShellAccountMutator(),
        refreshCoordinator: TestShellRefreshCoordinator = TestShellRefreshCoordinator(),
        deepLinkReplayer: TestShellDeepLinkReplayer = TestShellDeepLinkReplayer(),
        routerEffectHandler: TestShellRouterEffectHandler = TestShellRouterEffectHandler(),
        receiptLogger: TestShellReceiptLogger = TestShellReceiptLogger(),
        clock: TestShellClock = TestShellClock(now: Date(timeIntervalSince1970: 200))
    ) -> ShellStore {
        ShellStore(
            state: state,
            selectionPersistence: selectionPersistence,
            accountResolver: accountResolver,
            accountMutator: accountMutator,
            refreshCoordinator: refreshCoordinator,
            deepLinkReplayer: deepLinkReplayer,
            routerEffectHandler: routerEffectHandler,
            receiptLogger: receiptLogger,
            clock: clock
        )
    }

    @MainActor
    private func makeAccount(address: String, currentChain: Chain) -> EOAccount {
        let account = EOAccount(address: address)
        account.currentChain = currentChain
        return account
    }

    private func settleAsyncWork() async {
        await Task.yield()
        await Task.yield()
        await Task.yield()
    }
}

@MainActor
private final class TestShellSelectionPersistence: ShellSelectionPersisting {
    struct SavedSelection: Equatable {
        let address: String
        let chainID: String
    }

    var loadedSelection: (address: String, chainID: String)
    private(set) var savedSelections: [SavedSelection] = []
    private(set) var clearSelectionCallCount = 0

    init(loadedSelection: (address: String, chainID: String) = ("", Chain.ethMainnet.rawValue)) {
        self.loadedSelection = loadedSelection
    }

    func loadSelection() -> (address: String, chainID: String) {
        loadedSelection
    }

    func saveSelection(address: String, chainID: String) {
        savedSelections.append(SavedSelection(address: address, chainID: chainID))
    }

    func clearSelection() {
        clearSelectionCallCount += 1
    }
}

@MainActor
private final class TestShellAccountResolver: ShellAccountResolving {
    var accounts: [String: EOAccount]
    var fallback: EOAccount?

    init(accounts: [String: EOAccount] = [:], fallbackAccount: EOAccount? = nil) {
        self.accounts = accounts
        self.fallback = fallbackAccount
    }

    func account(for address: String) throws -> EOAccount? {
        accounts[address]
    }

    func fallbackAccount() throws -> EOAccount? {
        fallback
    }
}

@MainActor
private final class TestShellAccountMutator: ShellAccountMutating {
    enum Result<Value> {
        case success(Value)
        case failure(any Error)
    }

    private(set) var selectCalls: [(address: String, correlationID: String?)] = []
    private(set) var removeCalls: [(address: String, activeAddress: String, correlationID: String?)] = []
    private(set) var persistChainCalls: [(address: String, chain: Chain, correlationID: String?)] = []

    var selectResult: Result<EOAccount>
    var removeResult: Result<AccountRemovalResult>
    var persistChainResult: Result<EOAccount>

    init(
        selectResult: Result<EOAccount> = .failure(TestShellError.unused),
        removeResult: Result<AccountRemovalResult> = .failure(TestShellError.unused),
        persistChainResult: Result<EOAccount> = .failure(TestShellError.unused)
    ) {
        self.selectResult = selectResult
        self.removeResult = removeResult
        self.persistChainResult = persistChainResult
    }

    func selectAccount(address: String, correlationID: String?) async throws -> EOAccount {
        selectCalls.append((address, correlationID))
        switch selectResult {
        case .success(let account):
            return account
        case .failure(let error):
            throw error
        }
    }

    func removeAccount(address: String, activeAddress: String, correlationID: String?) async throws -> AccountRemovalResult {
        removeCalls.append((address, activeAddress, correlationID))
        switch removeResult {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    func persistCurrentChain(address: String, chain: Chain, correlationID: String?) async throws -> EOAccount {
        persistChainCalls.append((address, chain, correlationID))
        switch persistChainResult {
        case .success(let account):
            return account
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
private final class TestShellRefreshCoordinator: ShellRefreshing {
    struct RefreshCall: Equatable {
        let selection: ActiveShellSelection
        let correlationID: String?
    }

    var isLoading = false
    var refreshTTL: TimeInterval = 60
    var lastSuccessfulRefreshAtValue: Date?
    private(set) var refreshCalls: [RefreshCall] = []

    init(lastSuccessfulRefreshAt: Date? = nil) {
        self.lastSuccessfulRefreshAtValue = lastSuccessfulRefreshAt
    }

    func lastSuccessfulRefreshAt(for address: String, chain: Chain) -> Date? {
        lastSuccessfulRefreshAtValue
    }

    func refresh(selection: ActiveShellSelection, correlationID: String?) async {
        refreshCalls.append(RefreshCall(selection: selection, correlationID: correlationID))
    }
}

private final class TestShellDeepLinkReplayer: ShellDeepLinkReplaying {
    var nextResolution: PendingDeepLinkResolution
    private(set) var resolvedContexts: [PendingDeepLinkContext] = []

    init(
        nextResolution: PendingDeepLinkResolution = PendingDeepLinkResolution(
            chainOverride: nil,
            action: .wait
        )
    ) {
        self.nextResolution = nextResolution
    }

    func resolve(deepLink: AppDeepLink, context: PendingDeepLinkContext) -> PendingDeepLinkResolution {
        resolvedContexts.append(context)
        return nextResolution
    }
}

@MainActor
private final class TestShellRouterEffectHandler: ShellRouterEffectHandling {
    private(set) var effects: [ShellRoutingEffect] = []
    var routeError: AppRouteError?

    func handle(_ effect: ShellRoutingEffect) -> AppRouteError? {
        effects.append(effect)
        return routeError
    }
}

@MainActor
private final class TestShellReceiptLogger: ShellReceiptLogging {
    struct AppLaunch: Equatable {
        let address: String
        let chain: Chain
        let correlationID: String
    }

    private(set) var appLaunches: [AppLaunch] = []

    func recordAppLaunch(address: String, chain: Chain, correlationID: String) async {
        appLaunches.append(AppLaunch(address: address, chain: chain, correlationID: correlationID))
    }
}

private struct TestShellClock: ShellClock {
    let now: Date
}

private enum TestShellError: LocalizedError {
    case unused

    var errorDescription: String? {
        switch self {
        case .unused:
            return "Unused test path"
        }
    }
}
