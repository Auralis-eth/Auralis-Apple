import Foundation

public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let baseBackoff: TimeInterval
    public let breakerThreshold: Int
    private(set) public var consecutiveFailures: Int = 0
    private(set) public var circuitOpen: Bool = false

    public init(maxRetries: Int = 2, baseBackoff: TimeInterval = 0.75, breakerThreshold: Int = 5) {
        self.maxRetries = maxRetries
        self.baseBackoff = baseBackoff
        self.breakerThreshold = breakerThreshold
    }

    public func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        return baseBackoff * pow(2.0, Double(attempt - 1))
    }

    public mutating func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= breakerThreshold {
            circuitOpen = true
        }
    }

    public mutating func recordSuccess() {
        consecutiveFailures = 0
        circuitOpen = false
    }

    public mutating func reset() {
        consecutiveFailures = 0
        circuitOpen = false
    }
}
