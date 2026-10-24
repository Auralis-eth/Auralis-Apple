import Foundation

public enum AudioSessionEvent: Equatable, Sendable {
    case shouldPause
    case routeAvailable
    case spatialAudioEnabledChanged(Bool)
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
}

public protocol AudioSessionManaging: Sendable {
    var events: AsyncStream<AudioSessionEvent> { get }

    func configure() async throws
    func activate() async throws
    func deactivate() async throws
    func setSupportsMultichannelContent(_ supports: Bool) async throws
    func currentSpatialAudioEnabled() async -> Bool
}
