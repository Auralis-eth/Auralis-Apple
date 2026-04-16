import Foundation

enum SearchQueryKind: String, Equatable, Sendable {
    case empty
    case walletAddress
    case contractAddress
    case ambiguousAddress
    case invalidAddress
    case ensName
    case invalidENSLike
    case tokenSymbol
    case nftName
    case collectionName
    case text

    var title: String {
        switch self {
        case .empty:
            return "Start Typing"
        case .walletAddress:
            return "Wallet Address"
        case .contractAddress:
            return "Contract Address"
        case .ambiguousAddress:
            return "Address"
        case .invalidAddress:
            return "Invalid Address"
        case .ensName:
            return "ENS Name"
        case .invalidENSLike:
            return "Invalid ENS-Like Input"
        case .tokenSymbol:
            return "Token Symbol"
        case .nftName:
            return "NFT Name"
        case .collectionName:
            return "Collection"
        case .text:
            return "Text Query"
        }
    }

    var feedbackMessage: String {
        switch self {
        case .empty:
            return "Enter an ENS name, wallet address, contract address, token symbol, NFT name, or collection."
        case .walletAddress:
            return "Valid wallet address detected from local account data."
        case .contractAddress:
            return "Valid contract address detected from the active chain's local NFT data."
        case .ambiguousAddress:
            return "Valid address format detected, but local data cannot yet prove whether it is a wallet or contract."
        case .invalidAddress:
            return "This looks like an address, but it is not a valid Ethereum address."
        case .ensName:
            return "Valid ENS-style input detected. Resolution stays local-only in this slice."
        case .invalidENSLike:
            return "This looks domain-like, but it is not a valid `.eth` name."
        case .tokenSymbol:
            return "Short symbol-style input matched local token metadata."
        case .nftName:
            return "This query matches NFT item names in the active scope."
        case .collectionName:
            return "This query matches collection names in the active scope."
        case .text:
            return "Treating this as a general local text query."
        }
    }

    var isInvalidInput: Bool {
        switch self {
        case .invalidAddress, .invalidENSLike:
            return true
        default:
            return false
        }
    }
}
