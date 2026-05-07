import AuralisPrimaryModels
import Foundation

enum ProviderAbstractionError: LocalizedError, Equatable {
    case missingAPIKey(Secrets.APIKeyProvider)
    case unsupportedChain(Chain)
    case invalidURL
    case invalidAddress
    case badStatus(Int, message: String?)
    case invalidResponse
    case offline
    case unavailable
    case invalidBalancePayload
    case paginationStalled
    case unauthorized
    case rateLimited
    case unsupportedMethod
    case providerError(String)

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
        case .badStatus(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Provider returned HTTP \(statusCode): \(message)"
            }
            return "Provider returned HTTP \(statusCode)."
        case .invalidResponse:
            return "Provider returned an invalid response."
        case .offline:
            return "Provider could not be reached because this device appears to be offline."
        case .unavailable:
            return "Provider is temporarily unavailable."
        case .invalidBalancePayload:
            return "Provider returned an invalid native balance payload."
        case .paginationStalled:
            return "Provider pagination stalled before the response completed."
        case .unauthorized:
            return "Provider authentication failed."
        case .rateLimited:
            return "Provider is rate-limiting requests right now."
        case .unsupportedMethod:
            return "Provider does not support the requested RPC method."
        case .providerError(let message):
            return "Provider returned an RPC error: \(message)"
        }
    }
}
