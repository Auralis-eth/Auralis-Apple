import Foundation

struct ContextFreshness: Equatable, Sendable {
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
