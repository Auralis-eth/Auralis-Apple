import Foundation

public enum WalletConnectionState: Hashable, Sendable {
    case idle
    case initializing
    case restoring
    case pairingCreated
    case pairing
    case awaitingWalletLaunch
    case proposalPending
    case awaitingApproval
    case settling
    case connected
    case connectedOffline
    case disconnecting
    case expired
    case rejected(WalletConnectionError)
    case restorationFailed(WalletConnectionError)
    case disconnected
}

public struct WalletPairingPresentation: Identifiable, Hashable, Sendable {
    public var id: WalletPairingTopic { WalletPairingTopic(rawValue: pairingURI.topic) }

    public let provider: ThirdPartyWalletProvider
    public let pairingURI: WalletConnectURI
    public let qrPayload: String
    public let walletOpenURL: URL?
    public let expiryDate: Date
    public let state: WalletConnectionState

    public init(
        provider: ThirdPartyWalletProvider,
        pairingURI: WalletConnectURI,
        qrPayload: String? = nil,
        walletOpenURL: URL? = nil,
        expiryDate: Date,
        state: WalletConnectionState = .pairing
    ) {
        self.provider = provider
        self.pairingURI = pairingURI
        self.qrPayload = qrPayload ?? pairingURI.absoluteString
        self.walletOpenURL = walletOpenURL
        self.expiryDate = expiryDate
        self.state = state
    }

    /// Builds a pairing presentation from a connection start. Returns `nil` for
    /// direct request/response starts that carry no pairing URI.
    public init?(
        provider: ThirdPartyWalletProvider,
        start: WalletConnectionStart,
        expiryDate: Date,
        state: WalletConnectionState = .pairing
    ) {
        guard let pairingURI = start.pairingURI else { return nil }
        self.init(
            provider: provider,
            pairingURI: pairingURI,
            qrPayload: start.qrPayload,
            walletOpenURL: start.walletOpenURL,
            expiryDate: expiryDate,
            state: state
        )
    }
}

public struct WalletProviderErrorContext: Hashable, Codable, Sendable {
    public let providerID: WalletProviderID
    public let code: Int?
    public let message: String
    public let underlyingType: String?

    public init(providerID: WalletProviderID, code: Int? = nil, message: String, underlyingType: String? = nil) {
        self.providerID = providerID
        self.code = code
        self.message = message
        self.underlyingType = underlyingType
    }
}

public enum WalletSDKErrorMapper {
    public static func connectionError(
        context: WalletProviderErrorContext,
        fallback: WalletConnectionError = .invalidResponse
    ) -> WalletConnectionError {
        connectionError(
            providerID: context.providerID,
            code: context.code,
            message: context.message,
            fallback: fallback
        )
    }

    public static func connectionError(
        providerID: WalletProviderID? = nil,
        code: Int? = nil,
        message: String,
        fallback: WalletConnectionError = .invalidResponse
    ) -> WalletConnectionError {
        if let code {
            switch code {
            case 4001:
                return .userRejected
            case 4100:
                return .internalFailure(message)
            case 4900:
                // EIP-1193: disconnected from all chains.
                return .relayDisconnected
            case 4901:
                // EIP-1193: disconnected from the requested chain. The concrete
                // chain isn't recoverable from the code alone, so avoid
                // fabricating one and report it as a disconnect.
                return .relayDisconnected
            case 4902:
                // EIP-1193: unrecognized chain (wallet_switchEthereumChain).
                return .invalidChain(message)
            default:
                break
            }
        }

        let normalized = message.lowercased()
        if normalized.contains("reject") || normalized.contains("denied") || normalized.contains("declined") {
            return .userRejected
        }
        if normalized.contains("timeout") || normalized.contains("timed out") {
            return .requestTimedOut(WalletSignRequestID(rawValue: code.map(String.init) ?? "unknown"))
        }
        if normalized.contains("unsupported chain") {
            // The specific chain isn't parseable from a free-form message, so
            // preserve the original text rather than assuming Ethereum.
            return .invalidChain(message)
        }
        if normalized.contains("unsupported method") {
            return .unsupportedMethod(message)
        }
        if normalized.contains("not installed"), let providerID {
            return .walletNotInstalled(providerID)
        }
        if normalized.contains("disconnect") {
            return .relayDisconnected
        }
        return fallback
    }

    public static func failure(code: Int? = nil, message: String, data: String? = nil) -> WalletConnectorFailure {
        WalletConnectorFailure(code: code, message: message, data: data)
    }
}
