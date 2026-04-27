import Foundation

struct ContextSnapshot: Equatable, Sendable {
    let version: ContextSchemaVersion
    let mode: ContextField<String>
    let scope: ContextScope
    let balances: ContextBalancesSummary
    let libraryPointers: ContextLibraryPointers
    let modulePointers: ContextModulePointers
    let localPreferences: ContextLocalPreferences
    let freshness: ContextFreshness
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
        switch freshness.label {
        case "Unknown":
            return "Freshness Unknown"
        default:
            return freshness.label
        }
    }

    var modeDisplay: String {
        guard let modeValue = mode.value, !modeValue.isEmpty else {
            return "Unknown"
        }

        return modeValue.prefix(1).uppercased() + modeValue.dropFirst()
    }

    var selectedChainDisplayNames: String {
        guard let chains = scope.selectedChains.value, !chains.isEmpty else {
            return "No chain selected"
        }

        return chains.map(\.routingDisplayName).joined(separator: ", ")
    }

    var scopeSummary: String {
        "\(chromeAccountTitle) • \(selectedChainDisplayNames)"
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

    var modulePointersSummary: String {
        moduleSummaryItems(for: modulePointers.items)
    }

    var primaryModuleSummary: String {
        moduleSummaryItems(for: modulePointers.items.filter { $0.priority == .primary })
    }

    var shortcutModuleSummary: String {
        moduleSummaryItems(for: modulePointers.items.filter { $0.priority == .shortcut })
    }

    var pinnedModuleSummary: String {
        let pinnedItems = modulePointers.items.filter(\.isPinned)
        guard !pinnedItems.isEmpty else {
            return "No pinned shortcuts"
        }

        return pinnedItems.map(\.title).joined(separator: ", ")
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

    private func moduleSummaryItems(for items: [ContextModulePointer]) -> String {
        guard !items.isEmpty else {
            return "None"
        }

        return items.map(\.title).joined(separator: " • ")
    }
}
