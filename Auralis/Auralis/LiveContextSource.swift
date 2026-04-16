import Foundation

/// Live source implementation for Phase 0 context.
struct LiveContextSource: ContextSource {
    let accountProvider: () -> EOAccount?
    let addressProvider: () -> String
    let chainProvider: () -> Chain
    let modeProvider: () -> AppMode
    let loadingProvider: () -> Bool
    let refreshedAtProvider: () -> Date?
    let nativeBalanceDisplayProvider: () -> String?
    let nativeBalanceUpdatedAtProvider: () -> Date?
    let nativeBalanceProvenanceProvider: () -> ContextProvenance
    let freshnessTTLProvider: () -> TimeInterval?
    let trackedNFTCountProvider: () -> Int?
    let musicCollectionCountProvider: () -> Int?
    let receiptCountProvider: () -> Int?
    let pinnedActionsProvider: () -> [HomeLauncherAction]
    let prefersDemoDataProvider: () -> Bool?
    let pinnedItemCountProvider: () -> Int?

    init(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?,
        nativeBalanceDisplayProvider: @escaping () -> String? = { nil },
        nativeBalanceUpdatedAtProvider: @escaping () -> Date? = { nil },
        nativeBalanceProvenanceProvider: @escaping () -> ContextProvenance = { .localCache },
        freshnessTTLProvider: @escaping () -> TimeInterval? = { nil },
        trackedNFTCountProvider: @escaping () -> Int? = { nil },
        musicCollectionCountProvider: @escaping () -> Int? = { nil },
        receiptCountProvider: @escaping () -> Int? = { nil },
        pinnedActionsProvider: @escaping () -> [HomeLauncherAction] = { [] },
        prefersDemoDataProvider: @escaping () -> Bool? = { nil },
        pinnedItemCountProvider: @escaping () -> Int? = { nil }
    ) {
        self.accountProvider = accountProvider
        self.addressProvider = addressProvider
        self.chainProvider = chainProvider
        self.modeProvider = modeProvider
        self.loadingProvider = loadingProvider
        self.refreshedAtProvider = refreshedAtProvider
        self.nativeBalanceDisplayProvider = nativeBalanceDisplayProvider
        self.nativeBalanceUpdatedAtProvider = nativeBalanceUpdatedAtProvider
        self.nativeBalanceProvenanceProvider = nativeBalanceProvenanceProvider
        self.freshnessTTLProvider = freshnessTTLProvider
        self.trackedNFTCountProvider = trackedNFTCountProvider
        self.musicCollectionCountProvider = musicCollectionCountProvider
        self.receiptCountProvider = receiptCountProvider
        self.pinnedActionsProvider = pinnedActionsProvider
        self.prefersDemoDataProvider = prefersDemoDataProvider
        self.pinnedItemCountProvider = pinnedItemCountProvider
    }

    func snapshot() -> ContextSnapshot {
        let account = accountProvider()
        let selectedChain = chainProvider()
        let refreshTimestamp = refreshedAtProvider()

        return ContextSnapshot(
            version: .v0,
            mode: ContextField(
                modeProvider().rawValue,
                provenance: .localCache
            ),
            scope: ContextScope(
                accountAddress: ContextField(
                    account?.address ?? addressProvider(),
                    provenance: .userProvided,
                    updatedAt: account?.addedAt
                ),
                accountName: ContextField(
                    account?.name,
                    provenance: .localCache,
                    updatedAt: account?.mostRecentActivityAt
                ),
                selectedChains: ContextField(
                    [selectedChain],
                    provenance: .userProvided,
                    updatedAt: account?.mostRecentActivityAt
                )
            ),
            balances: ContextBalancesSummary(
                nativeBalanceDisplay: ContextField(
                    nativeBalanceDisplayProvider(),
                    provenance: nativeBalanceProvenanceProvider(),
                    updatedAt: nativeBalanceUpdatedAtProvider() ?? refreshTimestamp
                )
            ),
            libraryPointers: ContextLibraryPointers(
                trackedNFTCount: ContextField(
                    account?.trackedNFTCount ?? trackedNFTCountProvider(),
                    provenance: .localCache,
                    updatedAt: account?.mostRecentActivityAt
                ),
                musicCollectionCount: ContextField(
                    musicCollectionCountProvider(),
                    provenance: .localCache,
                    updatedAt: refreshTimestamp
                ),
                receiptCount: ContextField(
                    receiptCountProvider(),
                    provenance: .localCache,
                    updatedAt: refreshTimestamp
                )
            ),
            modulePointers: ContextModulePointers(
                items: HomeLauncherAction.allCases.map { action in
                    ContextModulePointer(
                        routeID: action.rawValue,
                        title: action.contextTitle,
                        priority: action.contextPriority,
                        isPinned: pinnedActionsProvider().contains(action),
                        isMounted: true
                    )
                }
            ),
            localPreferences: ContextLocalPreferences(
                prefersDemoData: ContextField(
                    prefersDemoDataProvider(),
                    provenance: .userProvided
                ),
                pinnedItemCount: ContextField(
                    pinnedItemCountProvider(),
                    provenance: .localCache,
                    updatedAt: refreshTimestamp
                )
            ),
            freshness: ContextFreshness(
                refreshState: loadingProvider() ? .refreshing : .idle,
                lastSuccessfulRefreshAt: refreshTimestamp,
                lastSuccessfulRefreshProvenance: .localCache,
                ttl: freshnessTTLProvider()
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
