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
    case avalanche
    case bnb
    case zksync
    case linea
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
        case .avalanche:
            "Avalanche"
        case .bnb:
            "BNB Smart Chain"
        case .zksync:
            "zkSync Era"
        case .linea:
            "Linea"
        case .solana:
            "Solana"
        }
    }

    public var namespace: String {
        switch self {
        case .ethereum, .polygon, .base, .optimism, .arbitrum, .avalanche, .bnb, .zksync, .linea:
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
        case .avalanche:
            "43114"
        case .bnb:
            "56"
        case .zksync:
            "324"
        case .linea:
            "59144"
        case .solana:
            Self.solanaMainnetReference
        }
    }

    public var caip2: String {
        "\(namespace):\(chainReference)"
    }

    public init?(caip2: String) {
        guard let chain = Self.allCases.first(where: { $0.caip2Values.contains(caip2) }) else {
            return nil
        }
        self = chain
    }

    public var caip2Values: Set<String> {
        Set([caip2]).union(caip2Aliases)
    }

    public var caip2Aliases: Set<String> {
        switch self {
        case .solana:
            return ["solana:mainnet"]
        case .ethereum, .polygon, .base, .optimism, .arbitrum, .avalanche, .bnb, .zksync, .linea:
            return []
        }
    }
}

public extension WalletChain {
    static let solanaMainnetReference = "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"
    static let solanaDevnetReference = "EtWTRABZaYq6iMfeYKouRu166VU2xqa1"
    static let solanaTestnetReference = "4uhcVJyU9pJkvQyS88uRDiswHXSCkY3z"

    static let evmChains: [WalletChain] = [.ethereum, .polygon, .base, .optimism, .arbitrum, .avalanche, .bnb, .zksync, .linea]
    static let defaultChains: [WalletChain] = WalletChain.evmChains
}

public extension WalletBlockchain {
    static let solanaMainnet = WalletBlockchain(namespace: "solana", reference: WalletChain.solanaMainnetReference)
    static let solanaDevnet = WalletBlockchain(namespace: "solana", reference: WalletChain.solanaDevnetReference)
    static let solanaTestnet = WalletBlockchain(namespace: "solana", reference: WalletChain.solanaTestnetReference)
}

public enum WalletProviderLaunchFamily: Hashable, Sendable {
    case walletConnect
    case directSDK
    case embeddedWallet
    case browserExtension
}

public struct WalletProviderConfigurationRequirements: Hashable, Sendable {
    public let querySchemes: [String]
    public let universalLinks: [String]
    public let mobileSDKIdentifiers: [String]

    public init(querySchemes: [String], universalLinks: [String], mobileSDKIdentifiers: [String]) {
        self.querySchemes = querySchemes
        self.universalLinks = universalLinks
        self.mobileSDKIdentifiers = mobileSDKIdentifiers
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
    public let role: WalletConnectorRole
    public let custodyModel: WalletCustodyModel
    public let supportStatus: WalletProviderSupportStatus
    private let explicitCapabilities: WalletConnectorCapabilities?

    public init(
        id: WalletProviderID,
        displayName: String,
        supportedChains: [WalletChain],
        connectionMethods: [WalletConnectionMethod],
        role: WalletConnectorRole = .dappConnectingToWallet,
        custodyModel: WalletCustodyModel = .externalSelfCustody,
        supportStatus: WalletProviderSupportStatus = .supported,
        capabilities: WalletConnectorCapabilities? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.supportedChains = supportedChains
        self.connectionMethods = connectionMethods
        self.role = role
        self.custodyModel = custodyModel
        self.supportStatus = supportStatus
        self.explicitCapabilities = capabilities
    }

    public var deepLinkScheme: String? {
        for method in connectionMethods {
            if case .deepLink(let scheme) = method {
                return Self.normalizedScheme(scheme)
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

    public var launchFamilies: Set<WalletProviderLaunchFamily> {
        Set(connectionMethods.map { method in
            switch method {
            case .universalLink, .deepLink:
                return .walletConnect
            case .mobileSDK(let identifier):
                if identifier.contains("privy") || identifier.contains("dynamic") {
                    return .embeddedWallet
                }
                return .directSDK
            case .browserExtension:
                return .browserExtension
            }
        })
    }

    public var requiresAuthenticationSession: Bool {
        role == .embeddedWalletProvider || launchFamilies.contains(.embeddedWallet)
    }

    public var capabilities: WalletConnectorCapabilities {
        if let explicitCapabilities {
            return explicitCapabilities
        }

        var value: WalletConnectorCapabilities = [.messageSigning, .transactionSigning]
        if supportedChains.contains(where: { WalletChain.evmChains.contains($0) }) {
            value.insert([.evm, .chainSwitching, .chainAddition, .assetWatching])
        }
        if supportedChains.contains(.solana) {
            value.insert([.solana, .batchTransactionSigning, .signAndSend])
        }
        if launchFamilies.contains(.embeddedWallet) {
            value.insert(.embeddedWallet)
        } else if launchFamilies.contains(.directSDK) {
            value.insert(.directRequestResponse)
        } else {
            value.insert(.externalWallet)
        }
        if configurationRequirements.universalLinks.isEmpty == false {
            value.insert(.universalLinkReturn)
        }
        if configurationRequirements.querySchemes.isEmpty == false {
            value.insert(.customSchemeReturn)
        }
        return value
    }

    public var configurationRequirements: WalletProviderConfigurationRequirements {
        WalletProviderConfigurationRequirements(
            querySchemes: connectionMethods.compactMap { method in
                if case .deepLink(let scheme) = method {
                    return Self.normalizedScheme(scheme)
                }
                return nil
            },
            universalLinks: connectionMethods.compactMap { method in
                if case .universalLink(let value) = method {
                    return value
                }
                return nil
            },
            mobileSDKIdentifiers: connectionMethods.compactMap { method in
                if case .mobileSDK(let identifier) = method {
                    return identifier
                }
                return nil
            }
        )
    }

    private static func normalizedScheme(_ scheme: String) -> String {
        let trimmed = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("://") ? String(trimmed.dropLast(3)) : trimmed
    }
}
