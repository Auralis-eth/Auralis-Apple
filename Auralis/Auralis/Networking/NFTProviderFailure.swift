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

        if let providerFailure = NFTProviderFailure.classifyProviderError(error) {
            self = providerFailure
            return
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

    private static func classifyProviderError(_ error: Error) -> NFTProviderFailure? {
        if let providerError = error as? ProviderAbstractionError {
            switch providerError {
            case .missingAPIKey:
                return NFTProviderFailure(
                    kind: .misconfigured,
                    message: "Auralis is missing collection-provider configuration on this build.",
                    isRetryable: false
                )
            case .invalidURL, .unauthorized:
                return NFTProviderFailure(
                    kind: .misconfigured,
                    message: "Auralis could not authenticate with the collection provider for this build.",
                    isRetryable: false
                )
            case .invalidAddress:
                return NFTProviderFailure(
                    kind: .invalidScope,
                    message: "This wallet address is invalid for the current refresh request.",
                    isRetryable: false
                )
            case .rateLimited:
                return NFTProviderFailure(
                    kind: .rateLimited,
                    message: "The collection provider is rate-limiting refreshes right now.",
                    isRetryable: true
                )
            case .invalidResponse, .invalidBalancePayload, .paginationStalled:
                return NFTProviderFailure(
                    kind: .invalidResponse,
                    message: "The collection provider returned data Auralis could not read.",
                    isRetryable: true
                )
            case .offline:
                return NFTProviderFailure(
                    kind: .offline,
                    message: "Auralis could not reach the collection provider because this device appears to be offline.",
                    isRetryable: true
                )
            case .unavailable:
                return NFTProviderFailure(
                    kind: .unavailable,
                    message: "Auralis could not reach the collection provider just now.",
                    isRetryable: true
                )
            case .unsupportedChain, .unsupportedMethod, .providerError, .badStatus:
                return NFTProviderFailure(
                    kind: .unavailable,
                    message: error.localizedDescription,
                    isRetryable: true
                )
            }
        }

        if let apiError = error as? AlchemyNFTService.APIError {
            switch apiError {
            case .badRequest,
                    .emptyOwner,
                    .invalidOwnerFormat,
                    .invalidContractAddress,
                    .invalidPageSize,
                    .tooManyContractAddresses,
                    .mutuallyExclusiveFilters,
                    .orderingNotSupportedOnNetwork,
                    .invalidTokenUriTimeout,
                    .invalidRequestTimeout:
                return NFTProviderFailure(
                    kind: .invalidScope,
                    message: apiError.localizedDescription,
                    isRetryable: false
                )
            case .unauthorized, .forbidden, .badURL:
                return NFTProviderFailure(
                    kind: .misconfigured,
                    message: apiError.localizedDescription,
                    isRetryable: false
                )
            case .rateLimited:
                return NFTProviderFailure(
                    kind: .rateLimited,
                    message: apiError.localizedDescription,
                    isRetryable: true
                )
            case .badServerResponse:
                return NFTProviderFailure(
                    kind: .invalidResponse,
                    message: "The collection provider returned data Auralis could not read.",
                    isRetryable: true
                )
            case .requestTimeout, .serverError, .httpError, .notFound:
                return NFTProviderFailure(
                    kind: .unavailable,
                    message: apiError.localizedDescription,
                    isRetryable: true
                )
            }
        }

        return nil
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
