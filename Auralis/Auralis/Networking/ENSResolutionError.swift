import Foundation

enum ENSResolutionError: LocalizedError, Equatable {
    case invalidENSName
    case invalidAddress
    case unavailableProvider
    case notFound
    case mappingChanged(ensName: String, cachedAddress: String, resolvedAddress: String)

    var errorDescription: String? {
        switch self {
        case .invalidENSName:
            return "Enter a valid ENS name ending in .eth."
        case .invalidAddress:
            return "Enter a valid Ethereum address."
        case .unavailableProvider:
            return "ENS lookup is temporarily unavailable."
        case .notFound:
            return "No ENS record was found."
        case .mappingChanged(let ensName, _, let resolvedAddress):
            return "\(ensName) now resolves to \(resolvedAddress). Confirm the updated address before continuing."
        }
    }
}
