import Foundation

struct NFTProviderFailure: Equatable {
    let kind: NFTProviderFailureKind
    let message: String
    let isRetryable: Bool

    private init(
        kind: NFTProviderFailureKind,
        message: String,
        isRetryable: Bool
    ) {
        self.kind = kind
        self.message = message
        self.isRetryable = isRetryable
    }

    init?(error: Error?) {
        guard let error else {
            return nil
        }

        if let fetcherError = error as? NFTFetcher.FetcherError {
            switch fetcherError {
            case .missingAPIKey:
                self = NFTProviderFailure(
                    kind: .misconfigured,
                    message: "Auralis is missing collection-provider configuration on this build.",
                    isRetryable: false
                )
            case .loadingAlreadyInProgress:
                self = NFTProviderFailure(
                    kind: .busy,
                    message: "A refresh is already running for this collection.",
                    isRetryable: false
                )
            case .invalidAccount:
                self = NFTProviderFailure(
                    kind: .invalidScope,
                    message: "This wallet address is invalid for the current refresh request.",
                    isRetryable: false
                )
            case .rateLimited:
                self = NFTProviderFailure(
                    kind: .rateLimited,
                    message: "The collection provider is rate-limiting refreshes right now.",
                    isRetryable: true
                )
            case .networkError(let wrappedError):
                self = NFTProviderFailure.classifyNetworkOrFallback(wrappedError)
            case .retryExhausted(let lastError):
                self = NFTProviderFailure.classifyNetworkOrFallback(lastError ?? fetcherError)
            }

            return
        }

        if error is DecodingError {
            self = NFTProviderFailure(
                kind: .invalidResponse,
                message: "The collection provider returned data Auralis could not read.",
                isRetryable: true
            )
            return
        }

        self = NFTProviderFailure.classifyNetworkOrFallback(error)
    }

    private static func classifyNetworkOrFallback(_ error: Error) -> NFTProviderFailure {
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
