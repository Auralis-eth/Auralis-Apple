import Foundation

public enum NFTProviderPublicErrorCode: String, Equatable, Sendable {
    case rateLimited
    case unauthorizedProviderConfiguration
    case providerUnavailable
    case invalidResponse
}

public struct NFTProviderFailure: Equatable, Sendable {
    public let kind: NFTProviderFailureKind
    public let message: String
    public let isRetryable: Bool

    public var publicErrorCode: NFTProviderPublicErrorCode {
        switch kind {
        case .rateLimited:
            return .rateLimited
        case .misconfigured:
            return .unauthorizedProviderConfiguration
        case .invalidResponse:
            return .invalidResponse
        case .offline, .invalidScope, .busy, .unavailable:
            return .providerUnavailable
        }
    }

    public init(
        kind: NFTProviderFailureKind,
        message: String,
        isRetryable: Bool
    ) {
        self.kind = kind
        self.message = message
        self.isRetryable = isRetryable
    }

    public static func classifyNetworkOrFallback(_ error: Error) -> NFTProviderFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return NFTProviderFailure(
                    kind: .offline,
                    message: "Auralis could not reach the collection provider because this device appears to be offline.",
                    isRetryable: true
                )
            case .timedOut, .cannotConnectToHost:
                return NFTProviderFailure(
                    kind: .unavailable,
                    message: "The collection provider did not respond in time.",
                    isRetryable: true
                )
            default:
                break
            }
        }

        return NFTProviderFailure(
            kind: .unavailable,
            message: "Auralis could not reach the collection provider just now.",
            isRetryable: true
        )
    }
}
