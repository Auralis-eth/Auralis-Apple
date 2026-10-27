public struct ContextSnapshot: Equatable, Sendable {
    public let version: ContextSchemaVersion
    public let mode: ContextField<String>
    public let scope: ContextScope
    public let balances: ContextBalancesSummary
    public let libraryPointers: ContextLibraryPointers
    public let modulePointers: ContextModulePointers
    public let localPreferences: ContextLocalPreferences
    public let freshness: ContextFreshness

    public init(
        version: ContextSchemaVersion,
        mode: ContextField<String>,
        scope: ContextScope,
        balances: ContextBalancesSummary,
        libraryPointers: ContextLibraryPointers,
        modulePointers: ContextModulePointers,
        localPreferences: ContextLocalPreferences,
        freshness: ContextFreshness
    ) {
        self.version = version
        self.mode = mode
        self.scope = scope
        self.balances = balances
        self.libraryPointers = libraryPointers
        self.modulePointers = modulePointers
        self.localPreferences = localPreferences
        self.freshness = freshness
    }

    public var chromeAccountTitle: String {
        if let accountName = scope.accountName.value, !accountName.isEmpty {
            return accountName
        }

        if let accountAddress = scope.accountAddress.value, !accountAddress.isEmpty {
            return abbreviatedAccountAddress(accountAddress)
        }

        return "No Account"
    }

    public var accountDisplay: String {
        if let accountName = scope.accountName.value, !accountName.isEmpty,
           let accountAddress = scope.accountAddress.value, !accountAddress.isEmpty {
            return "\(accountName) • \(abbreviatedAccountAddress(accountAddress))"
        }

        if let accountAddress = scope.accountAddress.value, !accountAddress.isEmpty {
            return abbreviatedAccountAddress(accountAddress)
        }

        return "No active account"
    }

    public var chainDisplay: String {
        scope.selectedChains.value?.first?.displayName ?? "No chain selected"
    }

    public var freshnessLabel: String {
        freshness.label == "Unknown" ? "Freshness Unknown" : freshness.label
    }

    public var modeDisplay: String {
        guard let modeValue = mode.value, !modeValue.isEmpty else {
            return "Unknown"
        }

        return modeValue.prefix(1).uppercased() + modeValue.dropFirst()
    }

    public var selectedChainDisplayNames: String {
        guard let chains = scope.selectedChains.value, !chains.isEmpty else {
            return "No chain selected"
        }

        return chains.map(\.displayName).joined(separator: ", ")
    }

    public var scopeSummary: String {
        "\(chromeAccountTitle) • \(selectedChainDisplayNames)"
    }

    public var librarySummary: String {
        [
            summaryItem(label: "NFTs", value: libraryPointers.trackedNFTCount.value),
            summaryItem(label: "Playlists", value: libraryPointers.musicCollectionCount.value),
            summaryItem(label: "Receipts", value: libraryPointers.receiptCount.value)
        ].joined(separator: " • ")
    }

    public var preferencesSummary: String {
        let demoData: String
        switch localPreferences.prefersDemoData.value {
        case true: demoData = "On"
        case false: demoData = "Off"
        case nil: demoData = "Unknown"
        }

        return [
            "Demo Data: \(demoData)",
            summaryItem(label: "Pinned Items", value: localPreferences.pinnedItemCount.value)
        ].joined(separator: " • ")
    }

    public var modulePointersSummary: String {
        moduleSummary(for: modulePointers.items)
    }

    public var primaryModuleSummary: String {
        moduleSummary(for: modulePointers.items.filter { $0.priority == .primary })
    }

    public var shortcutModuleSummary: String {
        moduleSummary(for: modulePointers.items.filter { $0.priority == .shortcut })
    }

    public var pinnedModuleSummary: String {
        let pinnedItems = modulePointers.items.filter(\.isPinned)
        return pinnedItems.isEmpty ? "No pinned shortcuts" : pinnedItems.map(\.title).joined(separator: ", ")
    }

    private func abbreviatedAccountAddress(_ address: String) -> String {
        guard address.count > 12 else {
            return address
        }

        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    private func summaryItem(label: String, value: Int?) -> String {
        "\(label): \(value.map(String.init) ?? "Unknown")"
    }

    private func moduleSummary(for items: [ContextModulePointer]) -> String {
        items.isEmpty ? "None" : items.map(\.title).joined(separator: " • ")
    }
}
