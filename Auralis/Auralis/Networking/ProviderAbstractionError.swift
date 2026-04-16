import Foundation

enum ProviderAbstractionError: LocalizedError, Equatable {
    case missingAPIKey(Secrets.APIKeyProvider)
    case unsupportedChain(Chain)
    case invalidURL
    case invalidAddress
    case invalidResponse
    case invalidBalancePayload

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider.rawValue)."
        case .unsupportedChain(let chain):
            return "Chain \(chain.rawValue) is not supported by this provider."
        case .invalidURL:
            return "Provider URL configuration is invalid."
        case .invalidAddress:
            return "The wallet address is invalid."
        case .invalidResponse:
            return "Provider returned an invalid response."
        case .invalidBalancePayload:
            return "Provider returned an invalid native balance payload."
        }
    }
}
