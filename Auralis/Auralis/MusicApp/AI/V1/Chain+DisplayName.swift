import Foundation

extension Chain {
    var displayName: String {
        switch self {
        case .ethMainnet:       return "Ethereum"
        case .polygonMainnet:   return "Polygon"
        case .arbMainnet:       return "Arbitrum"
        case .optMainnet:       return "Optimism"
        case .baseMainnet:      return "Base"
        default:                return rawValue.capitalized
        }
    }
}
