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

    public func url(pairingURI: WalletConnectURI, redirect: WalletConnectionRedirect? = nil) -> URL? {
        url(pairingURIString: pairingURI.absoluteString, redirect: redirect)
    }

    public func url(pairingURIString: String, redirect: WalletConnectionRedirect? = nil) -> URL? {
        let encoded = pairingURIString.walletConnectPercentEncoded
        var value = "\(scheme)://wc?uri=\(encoded)"
        if let redirectURL = redirect?.native.walletConnectPercentEncoded {
            value += "&redirectUrl=\(redirectURL)"
        }
        return URL(string: value)
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
    /// Namespaces published in the `wc_sessionPropose` request. Required vs
    /// optional intent is preserved so the wallet can settle a compliant session.
    public let requiredNamespaces: WalletNamespaceProposalSet
    public let optionalNamespaces: WalletNamespaceProposalSet

    public init(
        providerID: WalletProviderID,
        preferredChain: WalletChain? = nil,
        supportedChains: [WalletChain],
        metadata: WalletConnectionMetadata,
        callbackURL: URL? = nil,
        requiredNamespaces: WalletNamespaceProposalSet = .empty,
        optionalNamespaces: WalletNamespaceProposalSet = .defaultV1
    ) {
        self.providerID = providerID
        self.preferredChain = preferredChain
        self.supportedChains = supportedChains
        self.metadata = metadata
        self.callbackURL = callbackURL
        self.requiredNamespaces = requiredNamespaces
        self.optionalNamespaces = optionalNamespaces
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
    /// Whether the wallet has proven control of these accounts via a signing
    /// challenge. `false` until `WalletConnectDAppConnector.verifyOwnership`
    /// succeeds; a settled session only proves the wallet *claims* the address.
    public let addressVerified: Bool

    public init(
        id: WalletSessionID,
        topic: WalletPairingTopic,
        providerID: WalletProviderID,
        providerName: String,
        accounts: [WalletAccount],
        namespaces: [WalletSessionNamespace],
        connectedAt: Date = Date(),
        expiryDate: Date,
        addressVerified: Bool = false
    ) {
        self.id = id
        self.topic = topic
        self.providerID = providerID
        self.providerName = providerName
        self.accounts = accounts
        self.namespaces = namespaces
        self.connectedAt = connectedAt
        self.expiryDate = expiryDate
        self.addressVerified = addressVerified
    }

    private enum CodingKeys: String, CodingKey {
        case id, topic, providerID, providerName, accounts, namespaces, connectedAt, expiryDate, addressVerified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(WalletSessionID.self, forKey: .id)
        self.topic = try container.decode(WalletPairingTopic.self, forKey: .topic)
        self.providerID = try container.decode(WalletProviderID.self, forKey: .providerID)
        self.providerName = try container.decode(String.self, forKey: .providerName)
        self.accounts = try container.decode([WalletAccount].self, forKey: .accounts)
        self.namespaces = try container.decode([WalletSessionNamespace].self, forKey: .namespaces)
        self.connectedAt = try container.decode(Date.self, forKey: .connectedAt)
        self.expiryDate = try container.decode(Date.self, forKey: .expiryDate)
        self.addressVerified = try container.decodeIfPresent(Bool.self, forKey: .addressVerified) ?? false
    }

    public var connectorSession: WalletConnectorSession {
        WalletConnectorSession(
            id: id,
            topic: topic,
            providerID: providerID.rawValue,
            providerName: providerName,
            accounts: accounts,
            namespaces: namespaces,
            expiryDate: expiryDate,
            addressVerified: addressVerified
        )
    }
}

public enum WalletTransportEvent: Hashable, Sendable {
    case pairingCreated(WalletPairing)
    case sessionApproved(WalletSession)
    /// The wallet changed the session's namespaces/accounts (`wc_sessionUpdate`)
    /// or extended its expiry (`wc_sessionExtend`); carries the updated session.
    case sessionUpdated(WalletSession)
    /// The wallet emitted a session event (`wc_sessionEvent`), e.g.
    /// `accountsChanged` / `chainChanged`.
    case sessionEvent(WalletSessionEvent)
    case sessionRejected(WalletProviderID, WalletConnectionError)
    case sessionDeleted(WalletSessionID)
    case pairingExpired(WalletPairing)
    case requestExpired(WalletSignRequestID)
    case responseReceived(WalletResponse)
    case peerAcknowledgementFailed(WalletPeerAcknowledgementFailure)
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
    /// Publishes a `wc_sessionRequest` on the session topic and awaits the
    /// wallet's response, correlated by JSON-RPC id.
    func request(_ request: WalletRequest, topic: WalletPairingTopic) async throws -> WalletResponse
    func sessions() async throws -> [WalletSession]
    func events() -> AsyncStream<WalletTransportEvent>
    /// Records that the wallet has proven control of the session's accounts, so
    /// the session (and its persisted record) reports `addressVerified == true`.
    /// A no-op for transports that do not track verification.
    func markOwnershipVerified(topic: WalletPairingTopic) async throws
    /// Sends a liveness ping and awaits the peer's pong, throwing if the peer does
    /// not respond. A no-op for transports without a ping concept.
    func ping(topic: WalletPairingTopic) async throws
    /// Extends the session's expiry (clamped to the protocol cap), returning
    /// whether the expiry actually moved. A no-op returning `false` for transports
    /// that do not support extension.
    @discardableResult
    func extend(topic: WalletPairingTopic, to expiry: Date) async throws -> Bool
}

public extension WalletTransportClient {
    func markOwnershipVerified(topic: WalletPairingTopic) async throws {}
    func ping(topic: WalletPairingTopic) async throws {}
    @discardableResult
    func extend(topic: WalletPairingTopic, to expiry: Date) async throws -> Bool { false }
}

