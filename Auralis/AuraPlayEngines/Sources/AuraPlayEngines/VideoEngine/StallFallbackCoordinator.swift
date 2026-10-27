import Foundation

public struct StallFallbackDecision: Equatable, Sendable {
    public let shouldAttemptFallback: Bool
    public let resumeSeconds: Double

    public init(shouldAttemptFallback: Bool, resumeSeconds: Double) {
        self.shouldAttemptFallback = shouldAttemptFallback
        self.resumeSeconds = resumeSeconds
    }
}

public struct StallFallbackCoordinator: Sendable {
    public static let defaultThresholdSeconds: TimeInterval = 8

    public let thresholdSeconds: TimeInterval

    public init(thresholdSeconds: TimeInterval = Self.defaultThresholdSeconds) {
        self.thresholdSeconds = thresholdSeconds
    }

    public func decision(
        stalledDuration: TimeInterval,
        isGatewayURL: Bool,
        hasAlreadyRetried: Bool,
        lastKnownSeconds: Double
    ) -> StallFallbackDecision {
        StallFallbackDecision(
            shouldAttemptFallback: stalledDuration >= thresholdSeconds && isGatewayURL && !hasAlreadyRetried,
            resumeSeconds: lastKnownSeconds
        )
    }
}
