import Foundation

public struct ContextFreshness: Equatable, Sendable {
    public let refreshState: ContextRefreshState
    public let lastSuccessfulRefreshAt: Date?
    public let lastSuccessfulRefreshProvenance: ContextProvenance
    public let ttl: TimeInterval?
    public let referenceDate: Date

    public init(
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

    public var age: TimeInterval? {
        guard let lastSuccessfulRefreshAt else {
            return nil
        }

        return max(0, referenceDate.timeIntervalSince(lastSuccessfulRefreshAt))
    }

    public var isStale: Bool {
        guard refreshState != .refreshing, let ttl, let age else {
            return false
        }

        return age >= ttl
    }

    public var label: String {
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
