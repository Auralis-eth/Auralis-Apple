import Foundation

public struct AuraPlayQueueSnapshot: Equatable, Sendable {
    public let upcomingCount: Int
    public let historyCount: Int

    public init(upcomingCount: Int, historyCount: Int) {
        self.upcomingCount = upcomingCount
        self.historyCount = historyCount
    }
}

@MainActor
public protocol AuraPlayQueueCoordinating {
    func snapshot() -> AuraPlayQueueSnapshot
}
