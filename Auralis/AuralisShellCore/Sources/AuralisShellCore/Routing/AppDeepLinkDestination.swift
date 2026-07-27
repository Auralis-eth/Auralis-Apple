import AuralisPrimaryModels
import Foundation

public enum AppDeepLinkDestination: Hashable, Sendable {
    case nft(id: String)
    case token(contractAddress: String, chain: Chain?, symbol: String)
    case receipt(id: String)
    case auraPlayPlaylist(id: String)
    case auraPlayCollection(identifier: String, chain: Chain?)
    case auraPlayCreator(identifier: String)
}
