import Foundation
import SwiftData

protocol ShellContextSourceBuilding {
    func makeContextSource(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceDisplayProvider: @escaping () -> String?,
        nativeBalanceUpdatedAtProvider: @escaping () -> Date?,
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        prefersDemoDataProvider: @escaping () -> Bool?
    ) -> any ContextSource
}

@MainActor
protocol ShellContextServiceBuilding {
    func makeContextService(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceProvider: any NativeBalanceProviding,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        prefersDemoDataProvider: @escaping () -> Bool?
    ) -> ContextService
}

@MainActor
protocol ShellLibraryContextProviding {
    func playlistCount() -> Int?
    func receiptCount(scope: ReceiptTimelineScope) -> Int?
}

struct LiveShellContextSourceBuilder: ShellContextSourceBuilding {
    func makeContextSource(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceDisplayProvider: @escaping () -> String?,
        nativeBalanceUpdatedAtProvider: @escaping () -> Date?,
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        prefersDemoDataProvider: @escaping () -> Bool?
    ) -> any ContextSource {
        LiveContextSource(
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            nativeBalanceDisplayProvider: nativeBalanceDisplayProvider,
            nativeBalanceUpdatedAtProvider: nativeBalanceUpdatedAtProvider,
            nativeBalanceProvenanceProvider: nativeBalanceProvenanceProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            musicCollectionCountProvider: musicCollectionCountProvider,
            receiptCountProvider: receiptCountProvider,
            prefersDemoDataProvider: prefersDemoDataProvider
        )
    }
}

@MainActor
struct SwiftDataShellLibraryContextProvider: ShellLibraryContextProviding {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func playlistCount() -> Int? {
        do {
            return try modelContext.fetch(FetchDescriptor<Playlist>()).count
        } catch {
            return nil
        }
    }

    func receiptCount(scope: ReceiptTimelineScope) -> Int? {
        do {
            let receipts = try modelContext.fetch(FetchDescriptor<StoredReceipt>())
            return receipts
                .lazy
                .map(ReceiptTimelineRecord.init(storedReceipt:))
                .filter { $0.matches(scope) }
                .count
        } catch {
            return nil
        }
    }
}

@MainActor
struct LiveShellContextServiceBuilder: ShellContextServiceBuilding {
    private let contextSourceBuilder: any ShellContextSourceBuilding

    init(contextSourceBuilder: any ShellContextSourceBuilding = LiveShellContextSourceBuilder()) {
        self.contextSourceBuilder = contextSourceBuilder
    }

    func makeContextService(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceProvider: any NativeBalanceProviding,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        prefersDemoDataProvider: @escaping () -> Bool?
    ) -> ContextService {
        ContextService(
            contextSourceBuilder: contextSourceBuilder,
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            nativeBalanceProvider: nativeBalanceProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            musicCollectionCountProvider: musicCollectionCountProvider,
            receiptCountProvider: receiptCountProvider,
            prefersDemoDataProvider: prefersDemoDataProvider
        )
    }
}

@MainActor
protocol PolicyActionGating {
    func attempt(_ action: PolicyControlledAction) -> PolicyGateResult
}

@MainActor
struct PolicyActionGateService: PolicyActionGating {
    private let modeState: ModeState
    private let receiptStore: any ReceiptStore

    init(
        modeState: ModeState,
        receiptStore: any ReceiptStore
    ) {
        self.modeState = modeState
        self.receiptStore = receiptStore
    }

    func attempt(_ action: PolicyControlledAction) -> PolicyGateResult {
        ActionPolicyGate.attempt(
            action,
            modeState: modeState,
            receiptStore: receiptStore
        )
    }
}

@MainActor
struct ShellServiceHub {
    let modeStateFactory: @MainActor () -> ModeState
    let nftServiceFactory: @MainActor () -> NFTService
    let ensResolverFactory: @MainActor (ModelContext) -> any ENSResolving
    let readOnlyProviderFactory: ReadOnlyProviderFactory
    let accountStoreFactory: @MainActor (ModelContext) -> AccountStore
    let contextServiceBuilder: any ShellContextServiceBuilding
    let libraryContextProviderFactory: @MainActor (ModelContext) -> any ShellLibraryContextProviding
    let musicLibraryIndexerFactory: @MainActor (ModelContext) -> any MusicLibraryIndexing
    let receiptStoreFactory: @MainActor (ModelContext) -> any ReceiptStore
    let receiptEventLoggerFactory: @MainActor (ModelContext) -> ReceiptEventLogger
    let searchHistoryStoreFactory: () -> SearchHistoryStore
    let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> TokenHoldingsStore
    let policyActionHandlerFactory: @MainActor (ModelContext, ModeState) -> any PolicyActionGating

    static let live: ShellServiceHub = {
        let readOnlyProviderFactory = ReadOnlyProviderFactory()
        return ShellServiceHub(
            modeStateFactory: { ModeState() },
            nftServiceFactory: {
                NFTService(
                    nftFetcher: NFTFetcher(
                        nftProviderFactory: { chain in
                            try readOnlyProviderFactory.makeNFTInventoryProvider(for: chain)
                        }
                    )
                )
            },
            ensResolverFactory: { modelContext in
                ENSResolvers.live(modelContext: modelContext)
            },
            readOnlyProviderFactory: readOnlyProviderFactory,
            accountStoreFactory: { modelContext in
                AccountStore(
                    modelContext: modelContext,
                    eventRecorder: AccountEventRecorders.live(modelContext: modelContext)
                )
            },
            contextServiceBuilder: LiveShellContextServiceBuilder(),
            libraryContextProviderFactory: { modelContext in
                SwiftDataShellLibraryContextProvider(modelContext: modelContext)
            },
            musicLibraryIndexerFactory: { modelContext in
                SwiftDataMusicLibraryIndexer(modelContext: modelContext)
            },
            receiptStoreFactory: { modelContext in
                ReceiptStores.live(modelContext: modelContext)
            },
            receiptEventLoggerFactory: { modelContext in
                ReceiptEventLogger(
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                )
            },
            searchHistoryStoreFactory: {
                SearchHistoryStore()
            },
            tokenHoldingsStoreFactory: { modelContext in
                TokenHoldingsStore(modelContext: modelContext)
            },
            policyActionHandlerFactory: { modelContext, modeState in
                PolicyActionGateService(
                    modeState: modeState,
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                )
            }
        )
    }()
}
