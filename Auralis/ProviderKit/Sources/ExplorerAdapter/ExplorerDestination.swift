import AuralisPrimaryModels

public enum ExplorerDestination: Equatable, Sendable {
    case address(String, chain: Chain)
    case transaction(String, chain: Chain)
    case token(contract: String, chain: Chain)
    case nft(contract: String, tokenID: String, chain: Chain)
}
