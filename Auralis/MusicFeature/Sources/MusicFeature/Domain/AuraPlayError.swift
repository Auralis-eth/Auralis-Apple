import Foundation

public enum AuraPlayError: Error, Equatable, LocalizedError {
    case library(String)
    case playback(String)
    case queue(String)
    case artwork(String)
    case configuration(String)
    case mediaResolution(String)

    public var errorDescription: String? {
        switch self {
        case .library(let message):
            message
        case .playback(let message):
            message
        case .queue(let message):
            message
        case .artwork(let message):
            message
        case .configuration(let message):
            message
        case .mediaResolution(let message):
            message
        }
    }

    public static func library(_ error: Error) -> AuraPlayError {
        .library("AuraPlay could not load the music library summary yet: \(error.localizedDescription)")
    }

    public static func playback(_ error: Error) -> AuraPlayError {
        .playback("AuraPlay could not read playback state cleanly: \(error.localizedDescription)")
    }

    public static func queue(_ error: Error) -> AuraPlayError {
        .queue("AuraPlay could not inspect the playback queue: \(error.localizedDescription)")
    }

    public static func artwork(_ error: Error) -> AuraPlayError {
        .artwork("AuraPlay could not resolve artwork for the active track: \(error.localizedDescription)")
    }

    public static func mediaResolution(_ error: Error) -> AuraPlayError {
        .mediaResolution("AuraPlay could not resolve media storage URL: \(error.localizedDescription)")
    }
}
