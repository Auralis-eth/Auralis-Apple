import AuralisPrimaryModels

public enum ExplorerURLBuildError: Error, Equatable, Sendable {
    case unsupportedChain(Chain)
    case invalidAddress(String)
    case invalidTransactionHash(String)
    case invalidTokenID(String)
    case missingExplorerBaseURL(Chain)
}
