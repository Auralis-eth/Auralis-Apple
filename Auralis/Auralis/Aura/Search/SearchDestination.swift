import Foundation

enum SearchDestination: Equatable, Sendable {
    case profile(address: String)
    case token(contractAddress: String, chain: Chain, symbol: String)
    case nftItem(id: String)
    case nftCollection(contractAddress: String?, title: String, chain: Chain)
}
