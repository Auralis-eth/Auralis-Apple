import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation

struct SearchLocalMatch: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case account
        case ens
        case contract
        case tokenSymbol
        case nftName
        case collectionName
        case receipt
        case musicItem

        var title: String {
            switch self {
            case .account:
                return "Account"
            case .ens:
                return "ENS"
            case .contract:
                return "Contract"
            case .tokenSymbol:
                return "Symbol"
            case .nftName:
                return "NFT"
            case .collectionName:
                return "Collection"
            case .receipt:
                return "Receipt"
            case .musicItem:
                return "Music"
            }
        }
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let destination: SearchDestination

    var id: String {
        switch destination {
        case .profile(let address):
            return "\(kind.rawValue):profile:\(address)"
        case .token(let contractAddress, let chain, _):
            return "\(kind.rawValue):token:\(chain.rawValue):\(contractAddress)"
        case .nftItem(let id):
            return "\(kind.rawValue):nft:\(id)"
        case .nftCollection(let contractAddress, let title, let chain):
            return "\(kind.rawValue):collection:\(chain.rawValue):\(contractAddress ?? title)"
        case .receipt(let id):
            return "\(kind.rawValue):receipt:\(id)"
        case .musicItem(let id):
            return "\(kind.rawValue):music:\(id)"
        }
    }
}
