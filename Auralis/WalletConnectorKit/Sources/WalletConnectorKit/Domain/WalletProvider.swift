import Foundation

public struct WalletProviderID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public enum WalletChain: String, CaseIterable, Hashable, Sendable {
    case ethereum
    case polygon
    case base
    case optimism
    case arbitrum
    case solana

    public var displayName: String {
        switch self {
        case .ethereum:
            "Ethereum"
        case .polygon:
            "Polygon"
        case .base:
            "Base"
        case .optimism:
            "Optimism"
        case .arbitrum:
            "Arbitrum"
        case .solana:
            "Solana"
        }
    }
}

public enum WalletConnectionMethod: Hashable, Sendable {
    case universalLink(String)
    case deepLink(scheme: String)
    case mobileSDK(identifier: String)
    case browserExtension(identifier: String)

    public var displayName: String {
        switch self {
        case .universalLink:
            "Universal Link"
        case .deepLink:
            "Deep Link"
        case .mobileSDK:
            "Mobile SDK"
        case .browserExtension:
            "Browser Extension"
        }
    }
}

public struct ThirdPartyWalletProvider: Identifiable, Hashable, Sendable {
    public let id: WalletProviderID
    public let displayName: String
    public let supportedChains: [WalletChain]
    public let connectionMethods: [WalletConnectionMethod]

    public init(
        id: WalletProviderID,
        displayName: String,
        supportedChains: [WalletChain],
        connectionMethods: [WalletConnectionMethod]
    ) {
        self.id = id
        self.displayName = displayName
        self.supportedChains = supportedChains
        self.connectionMethods = connectionMethods
    }
}
