import Foundation

/// Compatibility model used by shell consumers that still need the compact
/// app-context shape derived from the shared `ContextSnapshot` contract.
struct AppContext: Equatable {
    let accountAddress: String
    let accountName: String?
    let chain: String
    let mode: String
    let isLoading: Bool
    let lastSuccessfulRefreshAt: Date?
    let freshnessTTL: TimeInterval?
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
