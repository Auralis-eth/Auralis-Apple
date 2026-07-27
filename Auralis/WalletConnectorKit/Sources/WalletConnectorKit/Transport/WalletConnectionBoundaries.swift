import Foundation

public protocol WalletApplicationOpening: Sendable {
    func canOpenURL(_ url: URL) async -> Bool
    func open(_ url: URL) async -> Bool
}

public struct WalletProviderDeepLink: Hashable, Sendable {
    public let providerID: WalletProviderID
    public let scheme: String

    public init(providerID: WalletProviderID, scheme: String) {
        self.providerID = providerID
        self.scheme = Self.normalizedScheme(scheme)
    }

    public func url(pairingURI: WalletConnectURI) -> URL? {
        URL(string: "\(scheme)://wc?uri=\(pairingURI.deeplinkURIValue)")
    }

    public func url(pairingURIString: String) -> URL? {
        let encoded = pairingURIString.walletConnectPercentEncoded
        return URL(string: "\(scheme)://wc?uri=\(encoded)")
    }

    private static func normalizedScheme(_ scheme: String) -> String {
        let trimmed = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("://") ? String(trimmed.dropLast(3)) : trimmed
    }
}

public struct WalletConnectionRedirect: Hashable, Sendable {
    public let native: String
    public let universal: String?
    public let linkMode: Bool

    public init(native: String, universal: String? = nil, linkMode: Bool = false) {
        self.native = native
        self.universal = universal
        self.linkMode = linkMode
    }
}

public struct WalletConnectionMetadata: Hashable, Sendable {
    public let appName: String
    public let appDescription: String
    public let appURL: URL
    public let iconURL: URL?
    public let redirect: WalletConnectionRedirect?

    public init(
        appName: String,
        appDescription: String,
        appURL: URL,
        iconURL: URL? = nil,
        redirect: WalletConnectionRedirect? = nil
    ) {
        self.appName = appName
        self.appDescription = appDescription
        self.appURL = appURL
        self.iconURL = iconURL
        self.redirect = redirect
    }
}

public struct WalletPairingRequest: Hashable, Sendable {
    public let providerID: WalletProviderID
    public let preferredChain: WalletChain?
    public let supportedChains: [WalletChain]
    public let metadata: WalletConnectionMetadata
    public let callbackURL: URL?

    public init(
        providerID: WalletProviderID,
        preferredChain: WalletChain? = nil,
        supportedChains: [WalletChain],
        metadata: WalletConnectionMetadata,
        callbackURL: URL? = nil
    ) {
        self.providerID = providerID
        self.preferredChain = preferredChain
        self.supportedChains = supportedChains
        self.metadata = metadata
        self.callbackURL = callbackURL
    }
}

public struct WalletSession: Identifiable, Hashable, Codable, Sendable {
    public let id: WalletSessionID
    public let topic: WalletPairingTopic
    public let providerID: WalletProviderID
    public let providerName: String
    public let accounts: [WalletAccount]
    public let namespaces: [WalletSessionNamespace]
    public let connectedAt: Date
    public let expiryDate: Date

    public init(
        id: WalletSessionID,
        topic: WalletPairingTopic,
        providerID: WalletProviderID,
        providerName: String,
        accounts: [WalletAccount],
        namespaces: [WalletSessionNamespace],
        connectedAt: Date = Date(),
        expiryDate: Date
    ) {
        self.id = id
        self.topic = topic
        self.providerID = providerID
        self.providerName = providerName
        self.accounts = accounts
        self.namespaces = namespaces
        self.connectedAt = connectedAt
        self.expiryDate = expiryDate
    }

    public var connectorSession: WalletConnectorSession {
        WalletConnectorSession(
            id: id,
            topic: topic,
            providerID: providerID.rawValue,
            providerName: providerName,
            accounts: accounts,
            namespaces: namespaces,
            expiryDate: expiryDate
        )
    }
}

public enum WalletTransportEvent: Hashable, Sendable {
    case pairingCreated(WalletPairing)
    case sessionApproved(WalletSession)
    case sessionRejected(WalletProviderID, WalletConnectionError)
    case sessionDeleted(WalletSessionID)
    case pairingExpired(WalletPairing)
    case requestExpired(WalletSignRequestID)
    case responseReceived(WalletResponse)
    case socketStatusChanged(WalletSocketStatus)
}

public enum WalletSocketStatus: String, Hashable, Codable, Sendable {
    case disconnected
    case connecting
    case connected
}

public protocol WalletTransportClient: Sendable {
    func createPairing(request: WalletPairingRequest) async throws -> WalletPairing
    func disconnect(topic: WalletPairingTopic) async throws
    func publish(_ request: WalletRequest, topic: WalletPairingTopic) async throws
    func sessions() async throws -> [WalletSession]
    func events() -> AsyncStream<WalletTransportEvent>
}

