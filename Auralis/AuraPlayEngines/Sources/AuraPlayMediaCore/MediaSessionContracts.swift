import Foundation

public enum MediaSessionEvent: Equatable, Sendable {
    case shouldPause
    case interruptionEndedShouldResume
    case enteredBackground
    case willStop
}

public protocol MediaSessionManaging: Sendable {
    var events: AsyncStream<MediaSessionEvent> { get }
    func configureForPlayback() async throws
}
