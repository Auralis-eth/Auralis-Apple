import Foundation

enum AppDeepLinkDestination: Hashable {
    case nft(id: String)
    case token(contractAddress: String, chain: Chain?, symbol: String)
    case receipt(id: String)
}
