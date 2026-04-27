@testable import Auralis
import Foundation
import Testing

@Suite
@MainActor
struct ShellStoreTests {
    @Test("restore from persistence reuses the resolved account selection")
    func restoreFromPersistenceUsesResolvedAccount() async {
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        account.currentChain = .baseMainnet

        let persistence = TestShellSelectionPersistence(
            address: account.address,
            chainID: Chain.ethMainnet.rawValue
        )
        let resolver = TestShellAccountResolver(accounts: [account], fallback: nil)
        let accountMutator = TestShellAccountMutator(accounts: [account])
        let refreshCoordinator = TestShellRefreshCoordinator()
        let routerHandler = TestShellRouterEffectHandler()
        let receiptLogger = TestShellReceiptLogger()
        let store = ShellStore(
            selectionPersistence: persistence,
            accountResolver: resolver,
            accountMutator: accountMutator,
            refreshCoordinator: refreshCoordinator,
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: routerHandler,
            receiptLogger: receiptLogger,
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(.restoreFromPersistence)

        #expect(store.state.selection == ActiveShellSelection(address: account.address, chain: .baseMainnet))
        #expect(store.state.activeAccountID == account.persistentModelID)
        #expect(store.state.didFinishInitialRestore)
        #expect(receiptLogger.recordedLaunches.count == 1)
        #expect(persistence.savedSelections.last?.address == account.address)
    }

    @Test("selecting a different account resets routes and triggers one refresh")
    func selectingDifferentAccountRefreshesOnce() async {
        let account = EOAccount(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        account.currentChain = .baseSepoliaTestnet

        let persistence = TestShellSelectionPersistence(
            address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            chainID: Chain.ethMainnet.rawValue
        )
        let refreshCoordinator = TestShellRefreshCoordinator()
        let routerHandler = TestShellRouterEffectHandler()
        let store = ShellStore(
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(accounts: [account], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [account]),
            refreshCoordinator: refreshCoordinator,
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: routerHandler,
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(
            .accountSelectionRequested(
                address: account.address,
                correlationID: "switch-1"
            )
        )
        await settleStore()

        #expect(store.state.selection == ActiveShellSelection(address: account.address, chain: .baseSepoliaTestnet))
        #expect(refreshCoordinator.refreshCalls.count == 1)
        #expect(routerHandler.effects.contains(.resetAllRoutes))
    }

    @Test("removing the active account falls back deterministically")
    func removingActiveAccountFallsBack() async {
        let active = EOAccount(address: "0x1111111111111111111111111111111111111111")
        active.currentChain = .ethMainnet
        let fallback = EOAccount(address: "0x2222222222222222222222222222222222222222")
        fallback.currentChain = .baseMainnet

        let persistence = TestShellSelectionPersistence(
            address: active.address,
            chainID: Chain.ethMainnet.rawValue
        )
        let accountMutator = TestShellAccountMutator(accounts: [active, fallback])
        accountMutator.removalFallback = fallback
        let routerHandler = TestShellRouterEffectHandler()
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: active.address, chain: .ethMainnet),
                activeAccountID: active.persistentModelID
            ),
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(accounts: [active, fallback], fallback: fallback),
            accountMutator: accountMutator,
            refreshCoordinator: TestShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: routerHandler,
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(
            .activeAccountRemovalRequested(
                address: active.address,
                correlationID: "remove-1"
            )
        )

        #expect(store.state.selection == ActiveShellSelection(address: fallback.address, chain: .baseMainnet))
        #expect(routerHandler.effects.contains(.resetAllRoutes))
        #expect(routerHandler.effects.contains(.selectTab(.home)))
        #expect(persistence.savedSelections.last?.address == fallback.address)
    }

    @Test("changing chain persists atomically and refreshes the new scope")
    func chainChangePersistsAndRefreshes() async {
        let account = EOAccount(address: "0x3333333333333333333333333333333333333333")
        account.currentChain = .ethMainnet

        let persistence = TestShellSelectionPersistence(
            address: account.address,
            chainID: Chain.ethMainnet.rawValue
        )
        let refreshCoordinator = TestShellRefreshCoordinator()
        let accountMutator = TestShellAccountMutator(accounts: [account])
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID
            ),
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(accounts: [account], fallback: nil),
            accountMutator: accountMutator,
            refreshCoordinator: refreshCoordinator,
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: TestShellRouterEffectHandler(),
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(
            .chainChangeRequested(
                chain: .baseMainnet,
                correlationID: "chain-1"
            )
        )
        await settleStore()

        #expect(store.state.selection == ActiveShellSelection(address: account.address, chain: .baseMainnet))
        #expect(accountMutator.persistedChainChanges.count == 1)
        #expect(accountMutator.persistedChainChanges.first?.0 == account.address)
        #expect(accountMutator.persistedChainChanges.first?.1 == .baseMainnet)
        #expect(refreshCoordinator.refreshCalls.count == 1)
    }

    @Test("scene active refreshes only stale scopes")
    func foregroundRefreshOnlyRunsForStaleSelection() async {
        let account = EOAccount(address: "0x4444444444444444444444444444444444444444")
        account.currentChain = .ethMainnet

        let refreshCoordinator = TestShellRefreshCoordinator()
        refreshCoordinator.lastSuccessful["\(account.address)|\(Chain.ethMainnet.rawValue)"] = Date(timeIntervalSince1970: 10)
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID
            ),
            selectionPersistence: TestShellSelectionPersistence(
                address: account.address,
                chainID: Chain.ethMainnet.rawValue
            ),
            accountResolver: TestShellAccountResolver(accounts: [account], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [account]),
            refreshCoordinator: refreshCoordinator,
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: TestShellRouterEffectHandler(),
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: Date(timeIntervalSince1970: 10 + refreshCoordinator.refreshTTL + 1))
        )

        await store.send(.sceneBecameActive)
        await settleStore()

        #expect(refreshCoordinator.refreshCalls.count == 1)
    }

    @Test("selecting the same account is a safe no-op")
    func selectingSameAccountDoesNotResetRoutesOrRefresh() async {
        let account = EOAccount(address: "0x5555555555555555555555555555555555555555")
        account.currentChain = .baseMainnet

        let refreshCoordinator = TestShellRefreshCoordinator()
        let routerHandler = TestShellRouterEffectHandler()
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .baseMainnet),
                activeAccountID: account.persistentModelID
            ),
            selectionPersistence: TestShellSelectionPersistence(
                address: account.address,
                chainID: Chain.baseMainnet.rawValue
            ),
            accountResolver: TestShellAccountResolver(accounts: [account], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [account]),
            refreshCoordinator: refreshCoordinator,
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: routerHandler,
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(
            .accountSelectionRequested(
                address: account.address,
                correlationID: "same-account"
            )
        )
        await settleStore()

        #expect(refreshCoordinator.refreshCalls.isEmpty)
        #expect(routerHandler.effects.isEmpty)
    }

    @Test("removing an inactive account leaves the active selection intact")
    func removingInactiveAccountDoesNotDisturbActiveSelection() async {
        let active = EOAccount(address: "0x6666666666666666666666666666666666666666")
        active.currentChain = .ethMainnet
        let inactive = EOAccount(address: "0x7777777777777777777777777777777777777777")

        let routerHandler = TestShellRouterEffectHandler()
        let persistence = TestShellSelectionPersistence(
            address: active.address,
            chainID: Chain.ethMainnet.rawValue
        )
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: active.address, chain: .ethMainnet),
                activeAccountID: active.persistentModelID
            ),
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(accounts: [active, inactive], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [active, inactive]),
            refreshCoordinator: TestShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: routerHandler,
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(
            .activeAccountRemovalRequested(
                address: inactive.address,
                correlationID: "remove-inactive"
            )
        )

        #expect(store.state.selection == ActiveShellSelection(address: active.address, chain: .ethMainnet))
        #expect(routerHandler.effects.isEmpty)
        #expect(persistence.clearCount == 0)
    }

    @Test("removing the last active account clears selection and persistence")
    func removingActiveAccountWithoutFallbackClearsSelection() async {
        let active = EOAccount(address: "0x8888888888888888888888888888888888888888")
        active.currentChain = .ethMainnet

        let persistence = TestShellSelectionPersistence(
            address: active.address,
            chainID: Chain.ethMainnet.rawValue
        )
        let routerHandler = TestShellRouterEffectHandler()
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: active.address, chain: .ethMainnet),
                activeAccountID: active.persistentModelID,
                pendingDeepLink: .destination(.receipt(id: "receipt-1"))
            ),
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(accounts: [active], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [active]),
            refreshCoordinator: TestShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: routerHandler,
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(
            .activeAccountRemovalRequested(
                address: active.address,
                correlationID: "remove-last"
            )
        )

        #expect(store.state.selection == nil)
        #expect(store.state.activeAccountID == nil)
        #expect(store.state.pendingDeepLink == nil)
        #expect(persistence.clearCount == 1)
        #expect(routerHandler.effects.contains(.resetAllRoutes))
        #expect(routerHandler.effects.contains(.selectTab(.home)))
    }

    @Test("chain persistence failure leaves shell state unchanged and surfaces an error")
    func chainChangeFailureRollsBackState() async {
        let account = EOAccount(address: "0x9999999999999999999999999999999999999999")
        account.currentChain = .ethMainnet

        let accountMutator = TestShellAccountMutator(accounts: [account])
        accountMutator.persistChainError = AccountStoreError.accountNotFound(account.address)
        let persistence = TestShellSelectionPersistence(
            address: account.address,
            chainID: Chain.ethMainnet.rawValue
        )
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID
            ),
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(accounts: [account], fallback: nil),
            accountMutator: accountMutator,
            refreshCoordinator: TestShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: TestShellRouterEffectHandler(),
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(
            .chainChangeRequested(
                chain: .baseMainnet,
                correlationID: "chain-fail"
            )
        )

        #expect(store.state.selection == ActiveShellSelection(address: account.address, chain: .ethMainnet))
        #expect(store.state.routeError?.title == "Chain Change Failed")
        #expect(persistence.savedSelections.isEmpty)
    }

    @Test("deep link for the current selection routes once the shell is ready")
    func deepLinkForCurrentSelectionRoutes() async {
        let account = EOAccount(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab")
        account.currentChain = .ethMainnet

        let routerHandler = TestShellRouterEffectHandler()
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID,
                didFinishInitialRestore: true
            ),
            selectionPersistence: TestShellSelectionPersistence(
                address: account.address,
                chainID: Chain.ethMainnet.rawValue
            ),
            accountResolver: TestShellAccountResolver(accounts: [account], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [account]),
            refreshCoordinator: TestShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: routerHandler,
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(.deepLinkReceived(.destination(.receipt(id: "receipt-42"))))

        #expect(
            routerHandler.effects.contains(
                .routeDeepLink(
                    destination: .receipt(id: "receipt-42"),
                    selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                    inheritedChain: nil
                )
            )
        )
        #expect(store.state.pendingDeepLink == nil)
    }

    @Test("deep link without an active account surfaces a route error")
    func deepLinkWithoutSelectionShowsRouteError() async {
        let store = ShellStore(
            state: ShellState(didFinishInitialRestore: true),
            selectionPersistence: TestShellSelectionPersistence(
                address: "",
                chainID: Chain.ethMainnet.rawValue
            ),
            accountResolver: TestShellAccountResolver(accounts: [], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: []),
            refreshCoordinator: TestShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: TestShellRouterEffectHandler(),
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(.deepLinkReceived(.destination(.receipt(id: "receipt-7"))))

        #expect(store.state.routeError?.title == "No Active Account")
        #expect(store.state.pendingDeepLink == nil)
    }

    @Test("route errors can be dismissed explicitly")
    func routeErrorDismissalClearsState() async {
        let store = ShellStore(
            state: ShellState(
                routeError: AppRouteError(
                    title: "Bad Link",
                    message: "Broken",
                    urlString: nil
                )
            ),
            selectionPersistence: TestShellSelectionPersistence(
                address: "",
                chainID: Chain.ethMainnet.rawValue
            ),
            accountResolver: TestShellAccountResolver(accounts: [], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: []),
            refreshCoordinator: TestShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: TestShellRouterEffectHandler(),
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(.routeErrorDismissed)

        #expect(store.state.routeError == nil)
    }

    @Test("scene active does not refresh when the scope is still fresh or already loading")
    func foregroundRefreshSkipsFreshAndLoadingScopes() async {
        let freshAccount = EOAccount(address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbc")
        freshAccount.currentChain = .ethMainnet
        let loadingAccount = EOAccount(address: "0xcccccccccccccccccccccccccccccccccccccccd")
        loadingAccount.currentChain = .baseMainnet

        let freshRefreshCoordinator = TestShellRefreshCoordinator()
        freshRefreshCoordinator.lastSuccessful["\(freshAccount.address)|\(Chain.ethMainnet.rawValue)"] = Date(timeIntervalSince1970: 990)
        let freshStore = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: freshAccount.address, chain: .ethMainnet),
                activeAccountID: freshAccount.persistentModelID
            ),
            selectionPersistence: TestShellSelectionPersistence(
                address: freshAccount.address,
                chainID: Chain.ethMainnet.rawValue
            ),
            accountResolver: TestShellAccountResolver(accounts: [freshAccount], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [freshAccount]),
            refreshCoordinator: freshRefreshCoordinator,
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: TestShellRouterEffectHandler(),
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: Date(timeIntervalSince1970: 1_000))
        )

        await freshStore.send(.sceneBecameActive)
        await settleStore()

        let loadingRefreshCoordinator = TestShellRefreshCoordinator()
        loadingRefreshCoordinator.isLoading = true
        let loadingStore = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: loadingAccount.address, chain: .baseMainnet),
                activeAccountID: loadingAccount.persistentModelID
            ),
            selectionPersistence: TestShellSelectionPersistence(
                address: loadingAccount.address,
                chainID: Chain.baseMainnet.rawValue
            ),
            accountResolver: TestShellAccountResolver(accounts: [loadingAccount], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [loadingAccount]),
            refreshCoordinator: loadingRefreshCoordinator,
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: TestShellRouterEffectHandler(),
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: Date(timeIntervalSince1970: 1_000))
        )

        await loadingStore.send(.sceneBecameActive)
        await settleStore()

        #expect(freshRefreshCoordinator.refreshCalls.isEmpty)
        #expect(loadingRefreshCoordinator.refreshCalls.isEmpty)
    }

    @Test("logout clears shell state and resets routing")
    func logoutClearsStateAndResetsRoutes() async {
        let account = EOAccount(address: "0xdddddddddddddddddddddddddddddddddddddddd")
        let persistence = TestShellSelectionPersistence(
            address: account.address,
            chainID: Chain.ethMainnet.rawValue
        )
        let routerHandler = TestShellRouterEffectHandler()
        let store = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID,
                pendingDeepLink: .destination(.receipt(id: "receipt-logout")),
                pendingCorrelationID: "logout-1",
                latestRefreshRequestID: UUID(),
                isRefreshingSelection: true,
                hasPresentedAuthenticatedExperience: true,
                didFinishInitialRestore: true,
                routeError: AppRouteError(title: "Oops", message: "Bad", urlString: nil)
            ),
            selectionPersistence: persistence,
            accountResolver: TestShellAccountResolver(accounts: [account], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [account]),
            refreshCoordinator: TestShellRefreshCoordinator(),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: routerHandler,
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )

        await store.send(.logoutRequested)

        #expect(store.state.selection == nil)
        #expect(store.state.activeAccountID == nil)
        #expect(store.state.pendingDeepLink == nil)
        #expect(store.state.pendingCorrelationID == nil)
        #expect(store.state.latestRefreshRequestID == nil)
        #expect(store.state.routeError == nil)
        #expect(persistence.clearCount == 1)
        #expect(routerHandler.effects.contains(.resetAllRoutes))
        #expect(routerHandler.effects.contains(.selectTab(.home)))
    }

    @Test("in-flight refresh does not keep the shell store alive without external ownership")
    func inFlightRefreshDoesNotRetainStore() async {
        let account = EOAccount(address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
        account.currentChain = .ethMainnet

        let refreshCoordinator = BlockingShellRefreshCoordinator()
        var store: ShellStore? = ShellStore(
            state: ShellState(
                selection: ActiveShellSelection(address: account.address, chain: .ethMainnet),
                activeAccountID: account.persistentModelID
            ),
            selectionPersistence: TestShellSelectionPersistence(
                address: account.address,
                chainID: Chain.ethMainnet.rawValue
            ),
            accountResolver: TestShellAccountResolver(accounts: [account], fallback: nil),
            accountMutator: TestShellAccountMutator(accounts: [account]),
            refreshCoordinator: refreshCoordinator,
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: TestShellRouterEffectHandler(),
            receiptLogger: TestShellReceiptLogger(),
            clock: TestShellClock(now: .init(timeIntervalSince1970: 1_000))
        )
        let weakStore = WeakBox(store)

        await store?.send(.refreshCurrentSelectionRequested(correlationID: "retain-check"))
        await refreshCoordinator.waitUntilRefreshStarts()
        store = nil
        await settleStore()

        #expect(weakStore.value == nil)

        refreshCoordinator.resume()
    }
}

@MainActor
private func settleStore() async {
    for _ in 0..<5 {
        await Task.yield()
    }
}

@MainActor
private final class TestShellSelectionPersistence: ShellSelectionPersisting {
    var address: String
    var chainID: String
    var savedSelections: [(address: String, chainID: String)] = []
    var clearCount = 0

    init(address: String, chainID: String) {
        self.address = address
        self.chainID = chainID
    }

    func loadSelection() -> (address: String, chainID: String) {
        (address, chainID)
    }

    func saveSelection(address: String, chainID: String) {
        self.address = address
        self.chainID = chainID
        savedSelections.append((address, chainID))
    }

    func clearSelection() {
        address = ""
        chainID = Chain.ethMainnet.rawValue
        clearCount += 1
    }
}

@MainActor
private final class TestShellAccountResolver: ShellAccountResolving {
    private var accountsByAddress: [String: EOAccount]
    private let fallback: EOAccount?

    init(accounts: [EOAccount], fallback: EOAccount?) {
        self.accountsByAddress = Dictionary(uniqueKeysWithValues: accounts.map { ($0.address, $0) })
        self.fallback = fallback
    }

    func account(for address: String) throws -> EOAccount? {
        accountsByAddress[address]
    }

    func fallbackAccount() throws -> EOAccount? {
        fallback
    }
}

@MainActor
private final class TestShellAccountMutator: ShellAccountMutating {
    private var accountsByAddress: [String: EOAccount]
    var removalFallback: EOAccount?
    var persistedChainChanges: [(String, Chain)] = []
    var persistChainError: Error?

    init(accounts: [EOAccount]) {
        self.accountsByAddress = Dictionary(uniqueKeysWithValues: accounts.map { ($0.address, $0) })
    }

    func selectAccount(address: String, correlationID: String?) async throws -> EOAccount {
        guard let account = accountsByAddress[address] else {
            throw AccountStoreError.accountNotFound(address)
        }
        return account
    }

    func removeAccount(address: String, activeAddress: String, correlationID: String?) async throws -> AccountRemovalResult {
        accountsByAddress.removeValue(forKey: address)
        return AccountRemovalResult(
            removedAddress: address,
            fallbackAccount: activeAddress == address ? removalFallback : nil
        )
    }

    func persistCurrentChain(address: String, chain: Chain, correlationID: String?) async throws -> EOAccount {
        if let persistChainError {
            throw persistChainError
        }
        guard let account = accountsByAddress[address] else {
            throw AccountStoreError.accountNotFound(address)
        }
        account.currentChain = chain
        persistedChainChanges.append((address, chain))
        return account
    }
}

@MainActor
private final class TestShellRefreshCoordinator: ShellRefreshing {
    var isLoading = false
    var refreshTTL: TimeInterval = 60
    var refreshCalls: [ActiveShellSelection] = []
    var lastSuccessful: [String: Date] = [:]

    func lastSuccessfulRefreshAt(for address: String, chain: Chain) -> Date? {
        lastSuccessful["\(address)|\(chain.rawValue)"]
    }

    func refresh(selection: ActiveShellSelection, correlationID: String?) async {
        refreshCalls.append(selection)
    }
}

@MainActor
private final class BlockingShellRefreshCoordinator: ShellRefreshing {
    var isLoading = false
    var refreshTTL: TimeInterval = 60

    private var didStartRefresh = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeWaiters: [CheckedContinuation<Void, Never>] = []

    func lastSuccessfulRefreshAt(for address: String, chain: Chain) -> Date? {
        nil
    }

    func refresh(selection: ActiveShellSelection, correlationID: String?) async {
        didStartRefresh = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            resumeWaiters.append(continuation)
        }
    }

    func waitUntilRefreshStarts() async {
        guard !didStartRefresh else {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume() {
        let waiters = resumeWaiters
        resumeWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private final class WeakBox<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}

private struct TestShellClock: ShellClock {
    let now: Date
}

@MainActor
private final class TestShellRouterEffectHandler: ShellRouterEffectHandling {
    var effects: [ShellRoutingEffect] = []

    func handle(_ effect: ShellRoutingEffect) -> AppRouteError? {
        effects.append(effect)
        return nil
    }
}

@MainActor
private final class TestShellReceiptLogger: ShellReceiptLogging {
    var recordedLaunches: [(String, Chain, String)] = []

    func recordAppLaunch(address: String, chain: Chain, correlationID: String) async {
        recordedLaunches.append((address, chain, correlationID))
    }
}
