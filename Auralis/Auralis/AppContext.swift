import Foundation

enum ContextSchemaVersion: String, Equatable, Sendable {
    case v0 = "p0.context.v0"
}

enum ContextProvenance: String, Equatable, Sendable {
    case userProvided = "user_provided"
    case onChain = "on_chain"
    case localCache = "local_cache"
}

struct ContextField<Value: Equatable>: Equatable {
    let value: Value?
    let provenance: ContextProvenance
    let updatedAt: Date?

    init(
        _ value: Value?,
        provenance: ContextProvenance,
        updatedAt: Date? = nil
    ) {
        self.value = value
        self.provenance = provenance
        self.updatedAt = updatedAt
    }
}

struct ContextScope: Equatable {
    let accountAddress: ContextField<String>
    let accountName: ContextField<String>
    let selectedChains: ContextField<[Chain]>
}

struct ContextBalancesSummary: Equatable {
    let nativeBalanceDisplay: ContextField<String>
}

struct ContextLibraryPointers: Equatable {
    let trackedNFTCount: ContextField<Int>
    let musicCollectionCount: ContextField<Int>
    let receiptCount: ContextField<Int>
}

struct ContextLocalPreferences: Equatable {
    let prefersDemoData: ContextField<Bool>
    let pinnedItemCount: ContextField<Int>
}

enum ContextRefreshState: String, Equatable, Sendable {
    case idle
    case refreshing
    case unknown
}

struct ContextFreshness: Equatable {
    let refreshState: ContextRefreshState
    let lastSuccessfulRefreshAt: Date?
    let lastSuccessfulRefreshProvenance: ContextProvenance
    let ttl: TimeInterval?

    var age: TimeInterval? {
        guard let lastSuccessfulRefreshAt else {
            return nil
        }

        return max(0, Date().timeIntervalSince(lastSuccessfulRefreshAt))
    }

    var isStale: Bool {
        guard refreshState != .refreshing, let ttl, let age else {
            return false
        }

        return age >= ttl
    }

    var label: String {
        if refreshState == .refreshing {
            return "Refreshing now"
        }

        guard let age else {
            return "Unknown"
        }

        if let ttl, age >= ttl {
            return "Stale"
        }

        if age < 60 {
            return "Fresh now"
        }

        if age < 3_600 {
            let minutes = Int(age / 60)
            return "\(minutes)m ago"
        }

        return "Stale"
    }
}

struct ContextSnapshot: Equatable {
    let version: ContextSchemaVersion
    let mode: ContextField<String>
    let scope: ContextScope
    let balances: ContextBalancesSummary
    let libraryPointers: ContextLibraryPointers
    let localPreferences: ContextLocalPreferences
    let freshness: ContextFreshness
}

/// Legacy compatibility model used by the current shell UI while `P0-401`
/// grows into the broader `ContextSnapshot` contract.
struct AppContext: Equatable {
    let accountAddress: String
    let accountName: String?
    let chain: String
    let mode: String
    let isLoading: Bool
    let lastSuccessfulRefreshAt: Date?
    let freshnessTTL: TimeInterval?
}

extension ContextSnapshot {
    var chromeAccountTitle: String {
        if let accountName = scope.accountName.value, !accountName.isEmpty {
            return accountName
        }

        if let accountAddress = scope.accountAddress.value, !accountAddress.isEmpty {
            return accountAddress.displayAddress
        }

        return "No Account"
    }

    var appContext: AppContext {
        AppContext(
            accountAddress: scope.accountAddress.value ?? "",
            accountName: scope.accountName.value,
            chain: scope.selectedChains.value?.first?.rawValue ?? "",
            mode: mode.value ?? "",
            isLoading: freshness.refreshState == .refreshing,
            lastSuccessfulRefreshAt: freshness.lastSuccessfulRefreshAt,
            freshnessTTL: freshness.ttl
        )
    }

    var accountDisplay: String {
        appContext.accountDisplay
    }

    var chainDisplay: String {
        appContext.chainDisplay
    }

    var freshnessLabel: String {
        freshness.label
    }

    var modeDisplay: String {
        mode.value ?? "Unknown"
    }

    var selectedChainDisplayNames: String {
        guard let chains = scope.selectedChains.value, !chains.isEmpty else {
            return "No chain selected"
        }

        return chains.map(\.routingDisplayName).joined(separator: ", ")
    }

    var scopeSummary: String {
        "\(accountDisplay) • \(selectedChainDisplayNames)"
    }

    var librarySummary: String {
        [
            librarySummaryItem(
                label: "NFTs",
                value: libraryPointers.trackedNFTCount.value
            ),
            librarySummaryItem(
                label: "Playlists",
                value: libraryPointers.musicCollectionCount.value
            ),
            librarySummaryItem(
                label: "Receipts",
                value: libraryPointers.receiptCount.value
            )
        ]
        .joined(separator: " • ")
    }

    var preferencesSummary: String {
        [
            booleanPreferenceSummary(
                label: "Demo Data",
                value: localPreferences.prefersDemoData.value
            ),
            integerPreferenceSummary(
                label: "Pinned Items",
                value: localPreferences.pinnedItemCount.value
            )
        ]
        .joined(separator: " • ")
    }

    private func librarySummaryItem(label: String, value: Int?) -> String {
        "\(label): \(value.map(String.init) ?? "Unknown")"
    }

    private func booleanPreferenceSummary(label: String, value: Bool?) -> String {
        let displayValue: String
        switch value {
        case true:
            displayValue = "On"
        case false:
            displayValue = "Off"
        case nil:
            displayValue = "Unknown"
        }
        return "\(label): \(displayValue)"
    }

    private func integerPreferenceSummary(label: String, value: Int?) -> String {
        "\(label): \(value.map(String.init) ?? "Unknown")"
    }
}

extension AppContext {
    init(snapshot: ContextSnapshot) {
        self = snapshot.appContext
    }

    var accountDisplay: String {
        if let accountName, !accountName.isEmpty {
            return "\(accountName) • \(accountAddress.displayAddress)"
        }

        if !accountAddress.isEmpty {
            return accountAddress.displayAddress
        }

        return "No active account"
    }

    var chainDisplay: String {
        guard let resolvedChain = Chain(rawValue: chain) else {
            return chain.isEmpty ? "No chain selected" : chain
        }

        return resolvedChain.routingDisplayName
    }

    var freshnessLabel: String {
        ContextFreshness(
            refreshState: isLoading ? .refreshing : .idle,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            lastSuccessfulRefreshProvenance: .localCache,
            ttl: freshnessTTL
        ).label
    }

    var chainScope: [Chain] {
        guard let resolvedChain = Chain(rawValue: chain) else {
            return []
        }

        return [resolvedChain]
    }
}

/// Protocol defining a context source providing snapshots.
protocol ContextSource {
    func snapshot() -> ContextSnapshot
}

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
