import Foundation

struct ContextFreshness: Equatable, Sendable {
    let refreshState: ContextRefreshState
    let lastSuccessfulRefreshAt: Date?
    let lastSuccessfulRefreshProvenance: ContextProvenance
    let ttl: TimeInterval?
    let referenceDate: Date

    init(
        refreshState: ContextRefreshState,
        lastSuccessfulRefreshAt: Date?,
        lastSuccessfulRefreshProvenance: ContextProvenance,
        ttl: TimeInterval?,
        referenceDate: Date = .now
    ) {
        self.refreshState = refreshState
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.lastSuccessfulRefreshProvenance = lastSuccessfulRefreshProvenance
        self.ttl = ttl
        self.referenceDate = referenceDate
    }

    var age: TimeInterval? {
        guard let lastSuccessfulRefreshAt else {
            return nil
        }

        return max(0, referenceDate.timeIntervalSince(lastSuccessfulRefreshAt))
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
