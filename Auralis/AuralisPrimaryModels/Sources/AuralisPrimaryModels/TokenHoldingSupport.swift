import Foundation

public enum TokenHoldingsMetadataFreshnessPolicy {
    public static let ttl: TimeInterval = 60 * 60 * 12

    public static func isStale(updatedAt: Date, now: Date = .now) -> Bool {
        max(0, now.timeIntervalSince(updatedAt)) >= ttl
    }
}

public extension Chain {
    var nativeTokenSymbol: String {
        switch self {
        case .polygonMainnet, .polygonAmoyTestnet:
            return "POL"
        case .solanaMainnet, .solanaDevnetTestnet:
            return "SOL"
        case .berachainMainnet:
            return "BERA"
        default:
            return "ETH"
        }
    }

    var nativeTokenDisplayName: String {
        switch self {
        case .polygonMainnet, .polygonAmoyTestnet:
            return "Polygon Native"
        case .solanaMainnet, .solanaDevnetTestnet:
            return "Solana Native"
        case .berachainMainnet:
            return "BeraChain Native"
        default:
            return "\(routingDisplayName) Native"
        }
    }
}
