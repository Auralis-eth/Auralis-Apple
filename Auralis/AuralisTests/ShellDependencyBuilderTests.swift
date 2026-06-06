import ReceiptsCore
import ReceiptStorage
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit
@testable import Auralis
import AuralisPrimaryModels
import AuralisTestSupport
import AuralisShellCore
import ENS
import Foundation
import MusicFeature
import SwiftData
import Testing
import TokenStorage

@Suite(.tags(.slow))
struct ShellDependencyBuilderTests {
    @MainActor
    private func makeIsolatedPinnedItemsStore() throws -> (store: HomePinnedItemsStore, cleanup: () -> Void) {
        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ShellDependencyBuilderTests")
        let store = HomePinnedItemsStore(
            userDefaults: defaults,
            storageKey: "\(HomePinnedItemsStore.storageDecisionIdentifier).tests"
        )
        return (store, cleanup)
    }

    @Test("gateway dependencies build account stores through the shared recorder seam")
    @MainActor
    func gatewayDependenciesUseSharedRecorderSeam() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let dependencies = AppEnvironment.live.accounts.makeGatewayDependencies(modelContext: context)
        let receiptStore = ReceiptStores.live(modelContext: context)

        _ = try await dependencies.featureDependencies.accountActivator.activateWatchAccount(
            from: "0x1234567890abcdef1234567890abcdef12345678",
            name: nil,
            source: .manualEntry,
            correlationID: "gateway-account-store"
        )

        let receipts = try await receiptStore.receipts(forCorrelationID: "gateway-account-store", limit: 10)
        #expect(receipts.map(\.kind) == ["account.selected", "account.added"])
    }

    @Test("main tab dependencies wire receipt logging through the shared receipt store")
    @MainActor
    func mainTabDependenciesUseSharedReceiptStore() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let dependencies = AppEnvironment.live.mainTabs.makeMainTabDependencies(modelContext: context)
        let receiptLogger = dependencies.receiptEventLoggerFactory(context)
        let receiptStore = ReceiptStores.live(modelContext: context)

        _ = try await receiptLogger.recordCopyAction(
            subject: "nft.id",
            value: "nft-123",
            surface: "tests.builder",
            correlationID: "main-tab-receipt-logger"
        )

        let receipts = try await receiptStore.receipts(forCorrelationID: "main-tab-receipt-logger", limit: 10)
        #expect(receipts.count == 1)
        #expect(try #require(receipts.first).trigger == "copy.performed")
    }

    @Test("main tab dependencies keep token holdings and pinned items on their intended seams")
    @MainActor
    func mainTabDependenciesExposeStableFeatureStores() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let (pinnedItemsStore, pinnedItemsCleanup) = try makeIsolatedPinnedItemsStore()
        defer { pinnedItemsCleanup() }
        let dependencies = AppEnvironment.live.mainTabs.makeMainTabDependencies(
            modelContext: context,
            homePinnedItemsStore: pinnedItemsStore
        )

        try await dependencies.tokenHoldingsStoreFactory(context).upsertNativeHolding(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            amountDisplay: "1.25 ETH",
            updatedAt: Date(timeIntervalSince1970: 123)
        )

        let holdings = try context.fetch(FetchDescriptor<TokenHolding>())
        #expect(holdings.count == 1)
        #expect(try #require(holdings.first).balanceKind == .native)
        #expect(try #require(holdings.first).amountDisplay == "1.25 ETH")

        let accountAddress = "0x\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(40))"
        let isPinned = try dependencies.homePinnedItemsStore.togglePin(.openSearch, accountAddress: accountAddress)
        #expect(isPinned)
        #expect(dependencies.homePinnedItemsStore.isPinned(.openSearch, accountAddress: accountAddress))
        #expect(dependencies.homePinnedItemsStore.pinnedCount(for: accountAddress) == 1)
    }

    @Test("feature assemblies build smoke-testable live collaborators")
    @MainActor
    func featureAssembliesBuildLiveCollaborators() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let environment = AppEnvironment.live

        _ = environment.providers.makeNativeBalanceProvider()
        _ = environment.providers.makeGasPricingProvider()
        _ = environment.providers.makeTokenHoldingsProvider()
        _ = environment.tokenHoldings.makeStore(modelContext: context)
        _ = environment.tokenHoldings.makeSyncer(modelContext: context)
        _ = environment.search.makeSearchHistoryStore(modelContext: context)
        _ = environment.home.makePinnedItemsStore()
        _ = environment.privacy.makeLogoutCleanupService(modelContext: context)

        let receiptLogger = environment.receipts.makeReceiptEventLogger(modelContext: context)
        _ = try await receiptLogger.recordCopyAction(
            subject: "assembly.smoke",
            value: "ok",
            surface: "tests.assemblies",
            correlationID: "assembly-receipt-logger"
        )

        let receipts = try await ReceiptStores.live(modelContext: context).receipts(
            forCorrelationID: "assembly-receipt-logger",
            limit: 10
        )
        #expect(receipts.count == 1)
    }

    @Test("shell bootstrap dependencies construct a live shell store that records app launch")
    @MainActor
    func shellBootstrapDependenciesConstructLiveShellStore() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let router = AppRouter()
        let selectionPersistence = RecordingShellSelectionPersistence()
        let store = ShellStore.live(
            dependencies: AppEnvironment.live.shell.makeShellStoreDependencies(
                modelContext: context,
                nftService: NFTService(),
                router: router,
                selectionPersistence: selectionPersistence
            )
        )

        await store.send(.restoreFromPersistence)

        let receipts = try await ReceiptStores.live(modelContext: context).latest(limit: 10)
        #expect(receipts.contains { $0.trigger == "app.launch" })
    }

    @Test("main tab dependencies wire policy gates through shared receipts and observe mode")
    @MainActor
    func mainTabDependenciesWirePolicyGate() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let dependencies = AppEnvironment.live.mainTabs.makeMainTabDependencies(modelContext: context)
        let (modeDefaults, modeDefaultsCleanup) = try TestSupport.temporaryUserDefaults(prefix: "ShellDependencyBuilderTests.ModeState")
        defer { modeDefaultsCleanup() }
        let modeState = ModeState(userDefaults: modeDefaults, storageKey: "app.mode.tests")

        let result = await dependencies.policyActionHandlerFactory(context, modeState).attempt(.signMessage)

        #expect(result.isAllowed == false)
        #expect(result.userMessage == "Not available in Observe mode")
        let receipts = try await ReceiptStores.live(modelContext: context).latest(limit: 10)
        #expect(receipts.contains { $0.trigger == "policy.denied" })
    }

    @Test("main tab dependencies wire privacy reset through shell preferences and pinned items")
    @MainActor
    func mainTabDependenciesWirePrivacyReset() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let auraPlayContainer = try AuraPlayModelContainer.make(inMemory: true)
        let (pinnedItemsStore, pinnedItemsCleanup) = try makeIsolatedPinnedItemsStore()
        defer { pinnedItemsCleanup() }
        let selectionPersistence = RecordingShellSelectionPersistence()
        let dependencies = AppEnvironment.live.mainTabs.makeMainTabDependencies(
            modelContext: context,
            homePinnedItemsStore: pinnedItemsStore,
            privacyResetServiceFactory: { modelContext, auraPlayContainer in
                PrivacyResetService(
                    transactionalResetService: SwiftDataTransactionalPrivacyResetService(
                        modelContainer: modelContext.container
                    ),
                    ensCacheResetService: ENSResolvers.cacheResetService(),
                    auraPlayPersistenceResetService: auraPlayContainer.map {
                        SwiftDataAuraPlayPersistenceResetService(modelContainer: $0)
                    } ?? AuraPlayStoreResetService(),
                    credentialResetService: RecordingCredentialPrivacyResetter(),
                    selectionPersistence: selectionPersistence,
                    homePinnedItemsStore: pinnedItemsStore
                )
            }
        )
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"

        try await selectionPersistence.saveSelection(address: accountAddress, chainID: Chain.baseMainnet.rawValue)
        _ = try dependencies.homePinnedItemsStore.togglePin(.openSearch, accountAddress: accountAddress)

        try await dependencies
            .privacyResetServiceFactory(context, auraPlayContainer)
            .resetLocalPrivacyData()

        let restoredSelection = try await selectionPersistence.loadSelection()
        #expect(restoredSelection.address.isEmpty)
        #expect(restoredSelection.chainID == Chain.ethMainnet.rawValue)
        #expect(dependencies.homePinnedItemsStore.isPinned(.openSearch, accountAddress: accountAddress) == false)
    }

    @Test("shell selection persistence save update load and clear use isolated service")
    @MainActor
    func shellSelectionPersistenceUsesCheckedOperations() async throws {
        let persistence = RecordingShellSelectionPersistence()
        let firstAddress = "0x1234567890abcdef1234567890abcdef12345678"
        let secondAddress = "0xabcdef1234567890abcdef1234567890abcdef12"

        try await persistence.clearSelection()

        try await persistence.saveSelection(address: firstAddress, chainID: Chain.ethMainnet.rawValue)
        var restoredSelection = try await persistence.loadSelection()
        #expect(restoredSelection.address == firstAddress)
        #expect(restoredSelection.chainID == Chain.ethMainnet.rawValue)

        try await persistence.saveSelection(address: secondAddress, chainID: Chain.baseMainnet.rawValue)
        restoredSelection = try await persistence.loadSelection()
        #expect(restoredSelection.address == secondAddress)
        #expect(restoredSelection.chainID == Chain.baseMainnet.rawValue)

        try await persistence.clearSelection()
        restoredSelection = try await persistence.loadSelection()
        #expect(restoredSelection.address.isEmpty)
        #expect(restoredSelection.chainID == Chain.ethMainnet.rawValue)
        #expect(persistence.clearSelectionCallCount == 2)
    }
}

@MainActor
private final class RecordingShellSelectionPersistence: ShellSelectionPersisting {
    private var selection: (address: String, chainID: String) = ("", Chain.ethMainnet.rawValue)
    private(set) var clearSelectionCallCount = 0

    func loadSelection() async throws -> (address: String, chainID: String) {
        selection
    }

    func saveSelection(address: String, chainID: String) async throws {
        selection = (address, chainID)
    }

    func clearSelection() async throws {
        selection = ("", Chain.ethMainnet.rawValue)
        clearSelectionCallCount += 1
    }
}

private actor RecordingCredentialPrivacyResetter: CredentialPrivacyResetting {
    private(set) var clearCount = 0

    func clearCredentials() async throws {
        clearCount += 1
    }
}
