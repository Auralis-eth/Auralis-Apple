import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import Foundation
import NFTKit
import PolicyCore
import ProviderKit
import ReceiptsCore
import ReceiptStorage
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
        nativeBalanceStatusMessageProvider: @escaping () -> String?,
        nativeBalanceUpdatedAtProvider: @escaping () -> Date?,
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
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
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
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
        nativeBalanceStatusMessageProvider: @escaping () -> String?,
        nativeBalanceUpdatedAtProvider: @escaping () -> Date?,
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance,
        freshnessTTLProvider: @escaping () -> TimeInterval?,
        trackedNFTCountProvider: @escaping () -> Int?,
        musicCollectionCountProvider: @escaping () -> Int?,
        receiptCountProvider: @escaping () -> Int?,
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
    ) -> any ContextSource {
        LiveContextSource(
            accountProvider: accountProvider,
            addressProvider: addressProvider,
            chainProvider: chainProvider,
            modeProvider: modeProvider,
            loadingProvider: loadingProvider,
            refreshedAtProvider: refreshedAtProvider,
            nativeBalanceDisplayProvider: nativeBalanceDisplayProvider,
            nativeBalanceStatusMessageProvider: nativeBalanceStatusMessageProvider,
            nativeBalanceUpdatedAtProvider: nativeBalanceUpdatedAtProvider,
            nativeBalanceProvenanceProvider: nativeBalanceProvenanceProvider,
            freshnessTTLProvider: freshnessTTLProvider,
            trackedNFTCountProvider: trackedNFTCountProvider,
            musicCollectionCountProvider: musicCollectionCountProvider,
            receiptCountProvider: receiptCountProvider,
            pinnedActionsProvider: pinnedActionsProvider,
            prefersDemoDataProvider: prefersDemoDataProvider,
            pinnedItemCountProvider: pinnedItemCountProvider
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
            return try modelContext.fetchCount(FetchDescriptor<Playlist>())
        } catch {
            return nil
        }
    }

    func receiptCount(scope: ReceiptTimelineScope) -> Int? {
        do {
            let normalizedAccountAddress = AuralisEthereumAddress.normalized(scope.accountAddress)
            let chainRawValue = scope.chain.rawValue
            let descriptor: FetchDescriptor<StoredReceipt>

            if let normalizedAccountAddress, !normalizedAccountAddress.isEmpty {
                descriptor = FetchDescriptor<StoredReceipt>(
                    predicate: #Predicate<StoredReceipt> { receipt in
                        receipt.accountAddress == normalizedAccountAddress &&
                        receipt.chainRawValue == chainRawValue
                    }
                )
            } else {
                descriptor = FetchDescriptor<StoredReceipt>()
            }

            return try modelContext.fetchCount(descriptor)
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
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction],
        prefersDemoDataProvider: @escaping () -> Bool?,
        pinnedItemCountProvider: @escaping () -> Int?
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
            pinnedActionsProvider: pinnedActionsProvider,
            prefersDemoDataProvider: prefersDemoDataProvider,
            pinnedItemCountProvider: pinnedItemCountProvider
        )
    }
}

@MainActor
struct ShellAssembly {
    private let accountAssembly: AccountAssembly
    private let receiptAssembly: ReceiptAssembly

    let contextServiceBuilder: any ShellContextServiceBuilding

    init(
        accountAssembly: AccountAssembly,
        receiptAssembly: ReceiptAssembly,
        contextServiceBuilder: any ShellContextServiceBuilding = LiveShellContextServiceBuilder()
    ) {
        self.accountAssembly = accountAssembly
        self.receiptAssembly = receiptAssembly
        self.contextServiceBuilder = contextServiceBuilder
    }

    func makeLibraryContextProvider(modelContext: ModelContext) -> any ShellLibraryContextProviding {
        SwiftDataShellLibraryContextProvider(modelContext: modelContext)
    }

    func makeShellStore(
        modelContext: ModelContext,
        nftService: NFTService,
        router: AppRouter,
        selectionPersistence: (any ShellSelectionPersisting)? = nil
    ) -> ShellStore {
        ShellStore.live(
            dependencies: makeShellStoreDependencies(
                modelContext: modelContext,
                nftService: nftService,
                router: router,
                selectionPersistence: selectionPersistence
            )
        )
    }

    func makeShellStoreDependencies(
        modelContext: ModelContext,
        nftService: NFTService,
        router: AppRouter,
        selectionPersistence: (any ShellSelectionPersisting)? = nil
    ) -> ShellStoreDependencies {
        let accountResolver = accountAssembly.makeShellAccountResolver(modelContext: modelContext)
        return ShellStoreDependencies(
            selectionPersistence: selectionPersistence ?? KeychainShellSelectionPersistence(),
            accountResolver: accountResolver,
            accountMutator: accountAssembly.makeShellAccountMutator(modelContext: modelContext),
            refreshCoordinator: NFTServiceShellRefreshCoordinator(
                modelContext: modelContext,
                nftService: nftService,
                accountResolver: accountResolver
            ),
            deepLinkReplayer: DefaultShellDeepLinkReplayer(),
            routerEffectHandler: AppRouterShellEffectHandler(
                router: router,
                modelContext: modelContext
            ),
            receiptLogger: receiptAssembly.makeShellReceiptLogger(modelContext: modelContext),
            clock: SystemShellClock()
        )
    }
}

