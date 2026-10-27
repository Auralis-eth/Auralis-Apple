import Foundation

public struct ContextSnapshotInput: Equatable, Sendable {
    public let mode: String
    public let accountAddress: String
    public let accountName: String?
    public let accountAddedAt: Date?
    public let accountMostRecentActivityAt: Date?
    public let selectedChains: [ContextChainReference]
    public let isRefreshing: Bool
    public let refreshedAt: Date?
    public let nativeBalanceDisplay: String?
    public let nativeBalanceStatusMessage: String?
    public let nativeBalanceUpdatedAt: Date?
    public let nativeBalanceProvenance: ContextProvenance
    public let freshnessTTL: TimeInterval?
    public let trackedNFTCount: Int?
    public let musicCollectionCount: Int?
    public let receiptCount: Int?
    public let modulePointers: [ContextModulePointer]
    public let prefersDemoData: Bool?
    public let pinnedItemCount: Int?
    public let referenceDate: Date

    public init(
        mode: String,
        accountAddress: String,
        accountName: String?,
        accountAddedAt: Date?,
        accountMostRecentActivityAt: Date?,
        selectedChains: [ContextChainReference],
        isRefreshing: Bool,
        refreshedAt: Date?,
        nativeBalanceDisplay: String?,
        nativeBalanceStatusMessage: String?,
        nativeBalanceUpdatedAt: Date?,
        nativeBalanceProvenance: ContextProvenance,
        freshnessTTL: TimeInterval?,
        trackedNFTCount: Int?,
        musicCollectionCount: Int?,
        receiptCount: Int?,
        modulePointers: [ContextModulePointer],
        prefersDemoData: Bool?,
        pinnedItemCount: Int?,
        referenceDate: Date
    ) {
        self.mode = mode
        self.accountAddress = accountAddress
        self.accountName = accountName
        self.accountAddedAt = accountAddedAt
        self.accountMostRecentActivityAt = accountMostRecentActivityAt
        self.selectedChains = selectedChains
        self.isRefreshing = isRefreshing
        self.refreshedAt = refreshedAt
        self.nativeBalanceDisplay = nativeBalanceDisplay
        self.nativeBalanceStatusMessage = nativeBalanceStatusMessage
        self.nativeBalanceUpdatedAt = nativeBalanceUpdatedAt
        self.nativeBalanceProvenance = nativeBalanceProvenance
        self.freshnessTTL = freshnessTTL
        self.trackedNFTCount = trackedNFTCount
        self.musicCollectionCount = musicCollectionCount
        self.receiptCount = receiptCount
        self.modulePointers = modulePointers
        self.prefersDemoData = prefersDemoData
        self.pinnedItemCount = pinnedItemCount
        self.referenceDate = referenceDate
    }
}

public struct ContextSnapshotBuilder: Sendable {
    public init() {}

    public func build(from input: ContextSnapshotInput) -> ContextSnapshot {
        ContextSnapshot(
            version: .v0,
            mode: ContextField(input.mode, provenance: .localCache),
            scope: ContextScope(
                accountAddress: ContextField(
                    input.accountAddress,
                    provenance: .userProvided,
                    updatedAt: input.accountAddedAt
                ),
                accountName: ContextField(
                    input.accountName,
                    provenance: .localCache,
                    updatedAt: input.accountMostRecentActivityAt
                ),
                selectedChains: ContextField(
                    input.selectedChains,
                    provenance: .userProvided,
                    updatedAt: input.accountMostRecentActivityAt
                )
            ),
            balances: ContextBalancesSummary(
                nativeBalanceDisplay: ContextField(
                    input.nativeBalanceDisplay,
                    provenance: input.nativeBalanceProvenance,
                    updatedAt: input.nativeBalanceUpdatedAt ?? input.refreshedAt
                ),
                nativeBalanceStatusMessage: ContextField(
                    input.nativeBalanceStatusMessage,
                    provenance: .localCache,
                    updatedAt: input.refreshedAt
                )
            ),
            libraryPointers: ContextLibraryPointers(
                trackedNFTCount: ContextField(
                    input.trackedNFTCount,
                    provenance: .localCache,
                    updatedAt: input.accountMostRecentActivityAt
                ),
                musicCollectionCount: ContextField(
                    input.musicCollectionCount,
                    provenance: .localCache,
                    updatedAt: input.refreshedAt
                ),
                receiptCount: ContextField(
                    input.receiptCount,
                    provenance: .localCache,
                    updatedAt: input.refreshedAt
                )
            ),
            modulePointers: ContextModulePointers(items: input.modulePointers),
            localPreferences: ContextLocalPreferences(
                prefersDemoData: ContextField(input.prefersDemoData, provenance: .userProvided),
                pinnedItemCount: ContextField(
                    input.pinnedItemCount,
                    provenance: .localCache,
                    updatedAt: input.refreshedAt
                )
            ),
            freshness: ContextFreshness(
                refreshState: input.isRefreshing ? .refreshing : .idle,
                lastSuccessfulRefreshAt: input.refreshedAt,
                lastSuccessfulRefreshProvenance: .localCache,
                ttl: input.freshnessTTL,
                referenceDate: input.referenceDate
            )
        )
    }
}
