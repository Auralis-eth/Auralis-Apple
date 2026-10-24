import Foundation

public enum AuraPlayError: Error, Equatable, LocalizedError {
    case network(AuraPlayNetworkError)
    case library(String)
    case playback(String)
    case queue(String)
    case artwork(String)
    case configuration(String)
    case mediaResolution(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .network(let error):
            error.errorDescription
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
        case .unknown(let message):
            message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .network:
            "Check your connection, wait briefly, then try syncing again."
        case .library:
            "Try refreshing the library. If the problem continues, reopen AuraPlay."
        case .playback:
            "Try the track again or choose another available media source."
        case .queue:
            "Try rebuilding the queue from the album, playlist, or library."
        case .artwork:
            "Playback can continue without artwork. Refresh the library to try loading it again."
        case .configuration:
            "Review the AuraPlay app configuration and relaunch the app."
        case .mediaResolution:
            "Try again to use another configured gateway, or choose a different track."
        case .unknown:
            "Try the action again. If the problem continues, reopen AuraPlay."
        }
    }

    public static func library(_ error: Error) -> AuraPlayError {
        .library(AuraPlayErrorPresentation.message(for: error, context: .librarySummary))
    }

    public static func playback(_ error: Error) -> AuraPlayError {
        .playback(AuraPlayErrorPresentation.message(for: error, context: .playback))
    }

    public static func queue(_ error: Error) -> AuraPlayError {
        .queue("AuraPlay could not inspect the playback queue. Please try again.")
    }

    public static func artwork(_ error: Error) -> AuraPlayError {
        .artwork(AuraPlayErrorPresentation.message(for: error, context: .artwork))
    }

    public static func mediaResolution(_ error: Error) -> AuraPlayError {
        .mediaResolution("AuraPlay could not resolve media for playback. Please try again.")
    }

    public static func normalized(_ error: Error) -> AuraPlayError {
        if let auraPlayError = error as? AuraPlayError {
            return auraPlayError
        }
        return .unknown("AuraPlay could not complete the request.")
    }
}

public enum AuraPlayNetworkError: Error, Equatable, LocalizedError {
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .rateLimited:
            "The NFT provider rate limit was reached. Try again later."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .rateLimited:
            "Wait a few minutes before refreshing the library again."
        }
    }
}
