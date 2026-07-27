import Foundation

public struct WalletProviderID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public enum WalletChain: String, CaseIterable, Hashable, Codable, Sendable {
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

    public var namespace: String {
        switch self {
        case .ethereum, .polygon, .base, .optimism, .arbitrum:
            "eip155"
        case .solana:
            "solana"
        }
    }

    public var chainReference: String {
        switch self {
        case .ethereum:
            "1"
        case .polygon:
            "137"
        case .base:
            "8453"
        case .optimism:
            "10"
        case .arbitrum:
            "42161"
        case .solana:
            "mainnet"
        }
    }

    public var caip2: String {
        "\(namespace):\(chainReference)"
    }

    public init?(caip2: String) {
        guard let chain = Self.allCases.first(where: { $0.caip2 == caip2 }) else {
            return nil
        }
        self = chain
    }
}

public extension WalletChain {
    static let evmChains: [WalletChain] = [.ethereum, .polygon, .base, .optimism, .arbitrum]
    static let defaultChains: [WalletChain] = WalletChain.evmChains
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

    public var deepLinkScheme: String? {
        for method in connectionMethods {
            if case .deepLink(let scheme) = method {
                return scheme
            }
        }
        return nil
    }

    public var supportsGenericPairingFallback: Bool {
        connectionMethods.contains {
            if case .browserExtension = $0 {
                return true
            }
            return false
        } || deepLinkScheme == nil
    }
}
