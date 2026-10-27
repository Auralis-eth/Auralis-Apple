import AuralisCrypto
import AuralisContext
import Foundation
import AuralisPolicy

/// Live source implementation for Phase 0 context.
struct LiveContextSource: ContextSource {
    let accountProvider: () -> EOAccount?
    let addressProvider: () -> String
    let chainProvider: () -> Chain
    let modeProvider: () -> CryptoMode
    let loadingProvider: () -> Bool
    let refreshedAtProvider: () -> Date?
    let nativeBalanceDisplayProvider: () -> String?
    let nativeBalanceStatusMessageProvider: () -> String?
    let nativeBalanceUpdatedAtProvider: () -> Date?
    let nativeBalanceProvenanceProvider: () -> ContextProvenance
    let freshnessTTLProvider: () -> TimeInterval?
    let trackedNFTCountProvider: () -> Int?
    let musicCollectionCountProvider: () -> Int?
    let receiptCountProvider: () -> Int?
    let pinnedActionsProvider: () -> [HomeLauncherAction]
    let prefersDemoDataProvider: () -> Bool?
    let pinnedItemCountProvider: () -> Int?
    let nowProvider: () -> Date

    init(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> CryptoMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceDisplayProvider: @escaping () -> String? = { nil },
        nativeBalanceStatusMessageProvider: @escaping () -> String? = { nil },
        nativeBalanceUpdatedAtProvider: @escaping () -> Date? = { nil },
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance = { .localCache },
        freshnessTTLProvider: @escaping () -> TimeInterval? = { nil },
        trackedNFTCountProvider: @escaping () -> Int? = { nil },
        musicCollectionCountProvider: @escaping () -> Int? = { nil },
        receiptCountProvider: @escaping () -> Int? = { nil },
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction] = { [] },
        prefersDemoDataProvider: @escaping () -> Bool? = { nil },
        pinnedItemCountProvider: @escaping () -> Int? = { nil },
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.accountProvider = accountProvider
        self.addressProvider = addressProvider
        self.chainProvider = chainProvider
        self.modeProvider = modeProvider
        self.loadingProvider = loadingProvider
        self.refreshedAtProvider = refreshedAtProvider
        self.nativeBalanceDisplayProvider = nativeBalanceDisplayProvider
        self.nativeBalanceStatusMessageProvider = nativeBalanceStatusMessageProvider
        self.nativeBalanceUpdatedAtProvider = nativeBalanceUpdatedAtProvider
        self.nativeBalanceProvenanceProvider = nativeBalanceProvenanceProvider
        self.freshnessTTLProvider = freshnessTTLProvider
        self.trackedNFTCountProvider = trackedNFTCountProvider
        self.musicCollectionCountProvider = musicCollectionCountProvider
        self.receiptCountProvider = receiptCountProvider
        self.pinnedActionsProvider = pinnedActionsProvider
        self.prefersDemoDataProvider = prefersDemoDataProvider
        self.pinnedItemCountProvider = pinnedItemCountProvider
        self.nowProvider = nowProvider
    }

    func snapshot() -> ContextSnapshot {
        let account = accountProvider()
        let selectedChain = chainProvider()
        let refreshTimestamp = refreshedAtProvider()
        let pinnedActions = pinnedActionsProvider()

        return ContextSnapshotBuilder().build(
            from: ContextSnapshotInput(
                mode: modeProvider().rawValue,
                accountAddress: account?.address ?? addressProvider(),
                accountName: account?.name,
                accountAddedAt: account?.addedAt,
                accountMostRecentActivityAt: account?.mostRecentActivityAt,
                selectedChains: [
                    ContextChainReference(
                        id: selectedChain.rawValue,
                        displayName: selectedChain.routingDisplayName
                    )
                ],
                isRefreshing: loadingProvider(),
                refreshedAt: refreshTimestamp,
                nativeBalanceDisplay: nativeBalanceDisplayProvider(),
                nativeBalanceStatusMessage: nativeBalanceStatusMessageProvider(),
                nativeBalanceUpdatedAt: nativeBalanceUpdatedAtProvider(),
                nativeBalanceProvenance: nativeBalanceProvenanceProvider(),
                freshnessTTL: freshnessTTLProvider(),
                trackedNFTCount: trackedNFTCountProvider() ?? account?.trackedNFTCount,
                musicCollectionCount: musicCollectionCountProvider(),
                receiptCount: receiptCountProvider(),
                modulePointers: HomeLauncherAction.allCases.map { action in
                    ContextModulePointer(
                        routeID: action.rawValue,
                        title: action.contextTitle,
                        priority: action.contextPriority,
                        isPinned: pinnedActions.contains(action),
                        isMounted: true
                    )
                },
                prefersDemoData: prefersDemoDataProvider(),
                pinnedItemCount: pinnedItemCountProvider(),
                referenceDate: nowProvider()
            )
        )
    }
}

private extension HomeLauncherAction {
    var contextTitle: String {
        switch self {
        case .openMusic:
            return "Music"
        case .openNFTTokens:
            return "NFT Tokens"
        case .openSearch:
            return "Search"
        case .openNews:
            return "News Feed"
        case .openReceipts:
            return "Receipts"
        }
    }

    var contextPriority: ContextModulePriority {
        switch self {
        case .openMusic, .openNFTTokens:
            return .primary
        case .openSearch, .openNews, .openReceipts:
            return .shortcut
        }
    }
}
