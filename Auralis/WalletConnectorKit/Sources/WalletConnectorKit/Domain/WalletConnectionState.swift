import Foundation

public enum WalletConnectionState: Hashable, Codable, Sendable {
    case idle
    case pairing
    case awaitingApproval
    case connected
    case rejected(WalletConnectionError)
    case expired
    case disconnected
}

public struct WalletPairingPresentation: Identifiable, Hashable, Sendable {
    public var id: WalletPairingTopic { pairingURI.topic }

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

    public init(
        provider: ThirdPartyWalletProvider,
        start: WalletConnectionStart,
        expiryDate: Date,
        state: WalletConnectionState = .pairing
    ) {
        self.init(
            provider: provider,
            pairingURI: start.pairingURI,
            qrPayload: start.qrPayload,
            walletOpenURL: start.walletOpenURL,
            expiryDate: expiryDate,
            state: state
        )
    }
}

public enum WalletSDKErrorMapper {
    public static func connectionError(
        providerID: WalletProviderID? = nil,
        code: Int? = nil,
        message: String,
        fallback: WalletConnectionError = .invalidResponse
    ) -> WalletConnectionError {
        let normalized = message.lowercased()
        if normalized.contains("reject") || normalized.contains("denied") || normalized.contains("declined") {
            return .userRejected
        }
        if normalized.contains("timeout") || normalized.contains("timed out") {
            return .requestTimedOut(WalletSignRequestID(rawValue: code.map(String.init) ?? "unknown"))
        }
        if normalized.contains("unsupported chain") {
            return .unsupportedChain(.ethereum)
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
