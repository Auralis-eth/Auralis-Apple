import Foundation

public struct PlaybackTick: Equatable, Codable, Sendable {
    public let currentSeconds: Double
    public let durationSeconds: Double?

    public init(currentSeconds: Double, durationSeconds: Double?) {
        self.currentSeconds = currentSeconds
        self.durationSeconds = durationSeconds
    }
}
