import Foundation

/// Minimal context schema for Phase 0.
struct AppContext: Equatable {
    let accountAddress: String
    let accountName: String?
    let chain: String
    let mode: String
    let isLoading: Bool
    let lastSuccessfulRefreshAt: Date?
}

extension AppContext {
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
            return chain
        }

        return resolvedChain.routingDisplayName
    }

    var freshnessLabel: String {
        if isLoading {
            return "Refreshing now"
        }

        guard let lastSuccessfulRefreshAt else {
            return "Unknown"
        }

        let age = Date().timeIntervalSince(lastSuccessfulRefreshAt)
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

/// Protocol defining a context source providing snapshots.
protocol ContextSource {
    func snapshot() -> AppContext
}

/// Live source implementation for Phase 0 context.
struct LiveContextSource: ContextSource {
    let accountProvider: () -> EOAccount?
    let addressProvider: () -> String
    let chainProvider: () -> Chain
    let modeProvider: () -> AppMode
    let loadingProvider: () -> Bool
    let refreshedAtProvider: () -> Date?

    init(
        accountProvider: @escaping () -> EOAccount?,
        addressProvider: @escaping () -> String,
        chainProvider: @escaping () -> Chain,
        modeProvider: @escaping () -> AppMode,
        loadingProvider: @escaping () -> Bool,
        refreshedAtProvider: @escaping () -> Date?
    ) {
        self.accountProvider = accountProvider
        self.addressProvider = addressProvider
        self.chainProvider = chainProvider
        self.modeProvider = modeProvider
        self.loadingProvider = loadingProvider
        self.refreshedAtProvider = refreshedAtProvider
    }

    func snapshot() -> AppContext {
        let account = accountProvider()
        return AppContext(
            accountAddress: account?.address ?? addressProvider(),
            accountName: account?.name,
            chain: chainProvider().rawValue,
            mode: modeProvider().rawValue,
            isLoading: loadingProvider(),
            lastSuccessfulRefreshAt: refreshedAtProvider()
        )
    }
}
