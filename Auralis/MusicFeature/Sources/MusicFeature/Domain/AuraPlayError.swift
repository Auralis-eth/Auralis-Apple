import Foundation

public enum AuraPlayError: Error, Equatable, LocalizedError {
    case network(AuraPlayNetworkError)
    case library(String)
    case playback(String)
    case queue(String)
    case artwork(String)
    case configuration(String)
    case mediaResolution(String)

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
}

public enum AuraPlayNetworkError: Error, Equatable, LocalizedError {
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .rateLimited:
            "The NFT provider rate limit was reached. Try again later."
        }
    }
}
