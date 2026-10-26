import Foundation

/// A bitset describing what a connector/provider can do (transport family,
/// chains, signing surface, session persistence, return-URL modes).
///
/// - Note: This is a **host-facing capability vocabulary** for gating and
///   telemetry. The registry/catalog does not yet filter on it internally — it is
///   deliberately available ahead of that wiring so hosts can describe and reason
///   about connectors today. Treat it as a stable, additive vocabulary; wiring it
///   into `WalletConnectorRegistry` filtering is tracked as forthcoming work.
public struct WalletConnectorCapabilities: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let persistentSession = WalletConnectorCapabilities(rawValue: 1 << 0)
    public static let externalWallet = WalletConnectorCapabilities(rawValue: 1 << 1)
    public static let embeddedWallet = WalletConnectorCapabilities(rawValue: 1 << 2)
    public static let evm = WalletConnectorCapabilities(rawValue: 1 << 3)
    public static let solana = WalletConnectorCapabilities(rawValue: 1 << 4)
    public static let messageSigning = WalletConnectorCapabilities(rawValue: 1 << 5)
    public static let transactionSigning = WalletConnectorCapabilities(rawValue: 1 << 6)
    public static let batchTransactionSigning = WalletConnectorCapabilities(rawValue: 1 << 7)
    public static let signAndSend = WalletConnectorCapabilities(rawValue: 1 << 8)
    public static let chainSwitching = WalletConnectorCapabilities(rawValue: 1 << 9)
    public static let chainAddition = WalletConnectorCapabilities(rawValue: 1 << 10)
    public static let assetWatching = WalletConnectorCapabilities(rawValue: 1 << 11)
    public static let universalLinkReturn = WalletConnectorCapabilities(rawValue: 1 << 12)
    public static let customSchemeReturn = WalletConnectorCapabilities(rawValue: 1 << 13)
    public static let directRequestResponse = WalletConnectorCapabilities(rawValue: 1 << 14)
    public static let walletConnectIRN = WalletConnectorCapabilities(rawValue: 1 << 15)
    public static let walletConnectLinkMode = WalletConnectorCapabilities(rawValue: 1 << 16)
}

public enum WalletConnectorRole: Hashable, Codable, Sendable {
    case dappConnectingToWallet
    case walletConnectingToDapp
    case embeddedWalletProvider
    case chainRPCClient
}

public enum WalletCustodyModel: Hashable, Codable, Sendable {
    case externalSelfCustody
    case embeddedSelfCustody
    case providerManaged
    case localKeyMaterial
    case none
}

public enum WalletProviderSupportStatus: Hashable, Codable, Sendable {
    case supported
    case limited(String)
    case deprecated(String)
    case unavailable(String)
}
