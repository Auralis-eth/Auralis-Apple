import Foundation

public struct WalletSessionID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public struct WalletPairingTopic: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public struct WalletPairingURI: Hashable, Codable, Sendable {
    public let topic: WalletPairingTopic
    public let absoluteString: String
    public let deeplinkURI: String
    public let expiryDate: Date?

    public init(topic: WalletPairingTopic, absoluteString: String, deeplinkURI: String, expiryDate: Date? = nil) {
        self.topic = topic
        self.absoluteString = absoluteString
        self.deeplinkURI = deeplinkURI
        self.expiryDate = expiryDate
    }
}

public struct WalletPairing: Identifiable, Hashable, Codable, Sendable {
    public var id: WalletPairingTopic { topic }

    public let topic: WalletPairingTopic
    public let providerID: WalletProviderID?
    public let uri: String?
    public let expiryDate: Date

    public init(
        topic: WalletPairingTopic,
        providerID: WalletProviderID? = nil,
        uri: String? = nil,
        expiryDate: Date
    ) {
        self.topic = topic
        self.providerID = providerID
        self.uri = uri
        self.expiryDate = expiryDate
    }

    public var isExpired: Bool {
        expiryDate <= Date()
    }
}

public struct WalletConnectorSession: Identifiable, Hashable, Codable, Sendable {
    public let id: WalletSessionID
    public let topic: WalletPairingTopic
    public let providerID: String
    public let providerName: String
    public let accounts: [WalletAccount]
    public let namespaces: [WalletSessionNamespace]
    public let expiryDate: Date
    /// Whether the connected wallet has *proven* control of these accounts via a
    /// connector-specific signing challenge.
    ///
    /// A settled session only proves the wallet **claims** these addresses.
    /// This is `false` until ownership is verified, so a consumer must never
    /// treat a `false` session's address as owned for anything sensitive.
    public let addressVerified: Bool

    public init(
        id: WalletSessionID,
        topic: WalletPairingTopic,
        providerID: String,
        providerName: String,
        accounts: [WalletAccount],
        namespaces: [WalletSessionNamespace],
        expiryDate: Date,
        addressVerified: Bool = false
    ) {
        self.id = id
        self.topic = topic
        self.providerID = providerID
        self.providerName = providerName
        self.accounts = accounts
        self.namespaces = namespaces
        self.expiryDate = expiryDate
        self.addressVerified = addressVerified
    }

    private enum CodingKeys: String, CodingKey {
        case id, topic, providerID, providerName, accounts, namespaces, expiryDate, addressVerified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(WalletSessionID.self, forKey: .id)
        self.topic = try container.decode(WalletPairingTopic.self, forKey: .topic)
        self.providerID = try container.decode(String.self, forKey: .providerID)
        self.providerName = try container.decode(String.self, forKey: .providerName)
        self.accounts = try container.decode([WalletAccount].self, forKey: .accounts)
        self.namespaces = try container.decode([WalletSessionNamespace].self, forKey: .namespaces)
        self.expiryDate = try container.decode(Date.self, forKey: .expiryDate)
        // Absent in records written before ownership tracking existed: default to
        // unverified so an old persisted session is never silently trusted.
        self.addressVerified = try container.decodeIfPresent(Bool.self, forKey: .addressVerified) ?? false
    }

    public var isExpired: Bool {
        expiryDate <= Date()
    }
}

public struct WalletConnectProtocolState: Hashable, Codable, Sendable {
    public let pairingTopic: WalletPairingTopic
    public let pairingSymmetricKey: String?
    public let pairingExpiryDate: Date
    public let sessionTopic: WalletPairingTopic?
    public let sessionSymmetricKey: String?
    public let sessionExpiryDate: Date?
    public let relayClientID: String?
    public let relayIdentityPublicKey: String?
    public let subscribedTopics: [WalletPairingTopic]
    public let namespaces: [WalletSessionNamespace]

    public init(
        pairingTopic: WalletPairingTopic,
        pairingSymmetricKey: String?,
        pairingExpiryDate: Date,
        sessionTopic: WalletPairingTopic? = nil,
        sessionSymmetricKey: String? = nil,
        sessionExpiryDate: Date? = nil,
        relayClientID: String? = nil,
        relayIdentityPublicKey: String? = nil,
        subscribedTopics: [WalletPairingTopic] = [],
        namespaces: [WalletSessionNamespace] = []
    ) {
        self.pairingTopic = pairingTopic
        self.pairingSymmetricKey = pairingSymmetricKey
        self.pairingExpiryDate = pairingExpiryDate
        self.sessionTopic = sessionTopic
        self.sessionSymmetricKey = sessionSymmetricKey
        self.sessionExpiryDate = sessionExpiryDate
        self.relayClientID = relayClientID
        self.relayIdentityPublicKey = relayIdentityPublicKey
        self.subscribedTopics = subscribedTopics
        self.namespaces = namespaces
    }

    public var restorationStatus: WalletConnectRestorationStatus {
        guard pairingSymmetricKey?.isEmpty == false else { return .missingPairingSymmetricKey }
        guard let sessionTopic else { return .pairingOnly }
        guard sessionSymmetricKey?.isEmpty == false else { return .missingSessionSymmetricKey(sessionTopic) }
        guard relayClientID?.isEmpty == false, relayIdentityPublicKey?.isEmpty == false else { return .missingRelayIdentity }
        if let sessionExpiryDate, sessionExpiryDate <= Date() { return .expiredSession(sessionTopic) }
        return .restorableSession(sessionTopic)
    }
}

public enum WalletConnectRestorationStatus: Hashable, Codable, Sendable {
    case restorableSession(WalletPairingTopic)
    case pairingOnly
    case missingPairingSymmetricKey
    case missingSessionSymmetricKey(WalletPairingTopic)
    case missingRelayIdentity
    case expiredSession(WalletPairingTopic)

    public var canResumeSession: Bool {
        if case .restorableSession = self { return true }
        return false
    }
}

public struct WalletConnectionRequest: Hashable, Sendable {
    public let preferredChain: WalletChain?
    public let callbackURL: URL?
    public let appName: String

    public init(
        preferredChain: WalletChain? = nil,
        callbackURL: URL? = nil,
        appName: String
    ) {
        self.preferredChain = preferredChain
        self.callbackURL = callbackURL
        self.appName = appName
    }
}

public struct WalletConnectionSession: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let providerID: WalletProviderID
    public let accountAddress: String
    public let chain: WalletChain
    public let connectedAt: Date

    public init(
        id: UUID = UUID(),
        providerID: WalletProviderID,
        accountAddress: String,
        chain: WalletChain,
        connectedAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.accountAddress = accountAddress
        self.chain = chain
        self.connectedAt = connectedAt
    }
}

public enum WalletConnectionError: Error, Hashable, Sendable {
    case invalidChain(String)
    case invalidAccount(String)
    case invalidPairingURI
    case pairingExpired
    case sessionExpired
    case walletNotInstalled(WalletProviderID)
    case walletOpenFailed(WalletProviderID)
    case userRejected
    case unsupportedProvider(WalletProviderID)
    case unsupportedChain(WalletChain)
    case unsupportedMethod(String)
    case unsupportedEvent(String)
    case relayDisconnected
    case relayAcknowledgementFailed(String)
    case requestTimedOut(WalletSignRequestID)
    case invalidResponse
    case cryptographyFailure
    case internalFailure(String)
    case unavailable(String)
    case cancelled
}

extension WalletConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidChain(let value):
            "Invalid wallet chain: \(value)."
        case .invalidAccount(let value):
            "Invalid wallet account: \(value)."
        case .invalidPairingURI:
            "The WalletConnect pairing URI is invalid."
        case .pairingExpired:
            "The wallet pairing expired."
        case .sessionExpired:
            "The wallet session expired."
        case .walletNotInstalled(let providerID):
            "Wallet provider \(providerID.rawValue) is not installed."
        case .walletOpenFailed(let providerID):
            "Wallet provider \(providerID.rawValue) could not be opened."
        case .userRejected:
            "The wallet request was rejected."
        case .unsupportedProvider(let providerID):
            "Wallet provider \(providerID.rawValue) is not supported."
        case .unsupportedChain(let chain):
            "Wallet chain \(chain.displayName) is not supported."
        case .unsupportedMethod(let method):
            "Wallet method \(method) is not supported."
        case .unsupportedEvent(let event):
            "Wallet event \(event) is not supported."
        case .relayDisconnected:
            "The wallet relay is disconnected."
        case .relayAcknowledgementFailed(let message):
            "The wallet relay did not acknowledge the request: \(message)."
        case .requestTimedOut(let requestID):
            "Wallet request \(requestID.rawValue) timed out."
        case .invalidResponse:
            "The wallet returned an invalid response."
        case .cryptographyFailure:
            "Wallet cryptography failed."
        case .internalFailure(let message):
            message
        case .unavailable(let message):
            message
        case .cancelled:
            "Wallet connection was cancelled."
        }
    }
}

public struct WalletConnectionStart: Hashable, Sendable {
    /// The WalletConnect pairing URI, when the connection uses a pairing
    /// handshake. `nil` for direct request/response wallets (e.g. Coinbase
    /// Mobile Wallet Protocol) that hand back an account synchronously.
    public let pairingURI: WalletConnectURI?
    public let walletOpenURL: URL?
    public let qrPayload: String

    public init(pairingURI: WalletConnectURI?, walletOpenURL: URL? = nil, qrPayload: String) {
        self.pairingURI = pairingURI
        self.walletOpenURL = walletOpenURL
        self.qrPayload = qrPayload
    }
}

public struct WalletPeerAcknowledgementFailure: Hashable, Sendable {
    public let topic: WalletPairingTopic
    public let requestID: Int64
    public let tag: Int
    public let error: WalletConnectionError

    public init(topic: WalletPairingTopic, requestID: Int64, tag: Int, error: WalletConnectionError) {
        self.topic = topic
        self.requestID = requestID
        self.tag = tag
        self.error = error
    }
}

public enum WalletConnectorEvent: Hashable, Sendable {
    case pairingCreated(WalletConnectURI)
    case sessionSettled(WalletConnectorSession)
    /// The wallet updated the session's namespaces/accounts or extended its
    /// expiry; carries the updated session.
    case sessionUpdated(WalletConnectorSession)
    /// The wallet emitted a session event (`accountsChanged` / `chainChanged`).
    case sessionEvent(WalletSessionEvent)
    case sessionRejected(WalletConnectionError)
    case sessionDeleted(WalletSessionID)
    case requestExpired(WalletSignRequestID)
    case responseReceived(WalletResponse)
    case peerAcknowledgementFailed(WalletPeerAcknowledgementFailure)
    case socketStatusChanged(WalletSocketStatus)
}

public enum WalletConnectorRuntimeFamily: Hashable, Codable, Sendable {
    case walletConnectSDK
    case customWalletConnectIRN
    case providerSDK
    case embeddedWallet
    case solanaRPC

    /// Whether a restored session's `addressVerified` flag can be trusted as-is
    /// for this family.
    ///
    /// Only the custom IRN transport persists and *maintains* the flag correctly:
    /// it clears `addressVerified` on an account-changing `wc_sessionUpdate`, so a
    /// wallet that swaps accounts after the connect-time proof restores as
    /// unverified. Vendor-SDK families cannot carry the flag in their own store,
    /// so their restored sessions always report `addressVerified == false` and
    /// must instead rely on the connect-time proof merged from the topic record.
    ///
    /// The lifecycle restore reads this to decide whether it may fall back to the
    /// topic record's `verified` bit: doing so for the IRN transport would
    /// re-trust swapped accounts across relaunch, because the topic bit is written
    /// at connect and never reset on update.
    public var restoredVerificationIsAuthoritative: Bool {
        self == .customWalletConnectIRN
    }
}

public enum WalletConnectorReadiness: Hashable, Codable, Sendable {
    case productionReady
    case experimental(String)
    case unavailable(String)

    public var allowsProductionUse: Bool {
        if case .productionReady = self {
            return true
        }
        return false
    }
}

public protocol WalletConnector: Sendable {
    var runtimeFamily: WalletConnectorRuntimeFamily { get }
    var readiness: WalletConnectorReadiness { get }
    var capabilities: WalletConnectorCapabilities { get }
    var events: AsyncStream<WalletConnectorEvent> { get }

    func connect(
        proposal: WalletNamespaceProposalSet,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart
    func handleCallback(url: URL) async throws
    func sessions() async throws -> [WalletConnectorSession]
    func disconnect(sessionId: WalletSessionID) async throws
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse

    /// Proves the connected wallet actually controls `address` by issuing a
    /// signing challenge and verifying the returned signature recovers it.
    ///
    /// **Fails closed.** The default implementation throws
    /// `WalletConnectionError.unavailable`, so a connector that cannot issue a
    /// challenge (or lacks a recovery-capable crypto provider) never reports a
    /// false "verified". Only override it where verification is genuinely
    /// supported. A `false`/throwing result means the address is merely
    /// *claimed* — never treat it as owned.
    @discardableResult
    func verifyOwnership(
        of address: String,
        chain: WalletChain,
        in sessionId: WalletSessionID,
        statement: String,
        expiryDate: Date
    ) async throws -> Bool
}

public extension WalletConnector {
    var runtimeFamily: WalletConnectorRuntimeFamily { .providerSDK }
    var readiness: WalletConnectorReadiness {
        .unavailable("Connector readiness must be declared explicitly before production use.")
    }
    var capabilities: WalletConnectorCapabilities {
        switch runtimeFamily {
        case .walletConnectSDK:
            [.persistentSession, .externalWallet, .evm, .solana, .messageSigning, .transactionSigning, .batchTransactionSigning, .signAndSend, .chainSwitching, .chainAddition, .assetWatching, .universalLinkReturn, .customSchemeReturn]
        case .customWalletConnectIRN:
            [.persistentSession, .externalWallet, .evm, .solana, .messageSigning, .transactionSigning, .batchTransactionSigning, .signAndSend, .walletConnectIRN, .customSchemeReturn]
        case .providerSDK:
            [.externalWallet, .messageSigning, .transactionSigning, .directRequestResponse]
        case .embeddedWallet:
            [.embeddedWallet, .evm, .solana, .messageSigning, .transactionSigning, .batchTransactionSigning, .signAndSend]
        case .solanaRPC:
            [.solana, .transactionSigning, .signAndSend]
        }
    }

    func connect(
        proposalRequest: WalletSessionProposalRequest = .defaultV1Optional,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart {
        try await connect(proposal: proposalRequest.mergedProposalSet, wallet: wallet)
    }

    /// Fail-closed default: a connector that does not implement ownership
    /// verification refuses rather than silently returning success. The default
    /// parameter values also let every connector be called ergonomically as
    /// `verifyOwnership(of:in:)` through the protocol.
    @discardableResult
    func verifyOwnership(
        of address: String,
        chain: WalletChain = .ethereum,
        in sessionId: WalletSessionID,
        statement: String = "Verify wallet ownership.",
        expiryDate: Date = Date().addingTimeInterval(300)
    ) async throws -> Bool {
        throw WalletConnectionError.unavailable(
            "Ownership verification is not supported by this connector. Inject or use a connector that can issue a signing challenge and verify the returned signature; treat a session's addressVerified == false as unproven."
        )
    }
}

public struct WalletConnectorFailure: Hashable, Codable, Sendable {
    public let code: Int?
    public let message: String
    public let data: String?

    public init(code: Int? = nil, message: String, data: String? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct WalletSignRequestID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

public struct WalletSignResult: Identifiable, Hashable, Codable, Sendable {
    public enum Outcome: Hashable, Codable, Sendable {
        case approved(String)
        case rejected(WalletConnectorFailure)
    }

    public let id: WalletSignRequestID
    public let topic: WalletPairingTopic?
    public let chain: WalletBlockchain?
    public let outcome: Outcome

    public init(
        id: WalletSignRequestID,
        topic: WalletPairingTopic? = nil,
        chain: WalletBlockchain? = nil,
        outcome: Outcome
    ) {
        self.id = id
        self.topic = topic
        self.chain = chain
        self.outcome = outcome
    }
}

public struct WalletSessionEvent: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let topic: WalletPairingTopic
    public let chain: WalletBlockchain?
    public let payload: String
    public let receivedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        topic: WalletPairingTopic,
        chain: WalletBlockchain? = nil,
        payload: String,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.topic = topic
        self.chain = chain
        self.payload = payload
        self.receivedAt = receivedAt
    }
}

public struct WalletAuthResult: Identifiable, Hashable, Codable, Sendable {
    public enum Outcome: Hashable, Codable, Sendable {
        case approved(session: WalletConnectorSession?, cacaoCount: Int)
        case rejected(WalletConnectorFailure)
    }

    public let id: String
    public let outcome: Outcome

    public init(id: String, outcome: Outcome) {
        self.id = id
        self.outcome = outcome
    }
}

public struct WalletSIWEResult: Identifiable, Hashable, Codable, Sendable {
    public enum Outcome: Hashable, Codable, Sendable {
        case approved(message: String, signature: String)
        case rejected(WalletConnectorFailure)
    }

    public let id: UUID
    public let outcome: Outcome

    public init(id: UUID = UUID(), outcome: Outcome) {
        self.id = id
        self.outcome = outcome
    }
}

public struct WalletSIWEAuthRequestParams: Hashable, Codable, Sendable {
    public let domain: String
    public let chains: [String]
    public let nonce: String
    public let uri: String
    public let notBefore: String?
    public let expiration: String?
    public let statement: String?
    public let requestId: String?
    public let resources: [String]?
    public let methods: [String]?
    public let signatureTypes: [String: [String]]?
    public let ttl: TimeInterval

    public init(
        domain: String,
        chains: [String],
        nonce: String,
        uri: String,
        notBefore: String? = nil,
        expiration: String? = nil,
        statement: String? = nil,
        requestId: String? = nil,
        resources: [String]? = nil,
        methods: [String]? = nil,
        signatureTypes: [String: [String]]? = nil,
        ttl: TimeInterval = 3600
    ) {
        self.domain = domain
        self.chains = chains
        self.nonce = nonce
        self.uri = uri
        self.notBefore = notBefore
        self.expiration = expiration
        self.statement = statement
        self.requestId = requestId
        self.resources = resources
        self.methods = methods
        self.signatureTypes = signatureTypes
        self.ttl = ttl
    }
}

public enum WalletConnectionLifecycleEvent: Identifiable, Hashable, Codable, Sendable {
    case approved(WalletConnectorSession)
    case rejected(WalletConnectorFailure)
    case disconnected(topic: WalletPairingTopic, reason: WalletConnectorFailure)
    case expired(WalletConnectorSession)
    case updated(WalletConnectorSession)
    case auth(WalletAuthResult)
    case siwe(WalletSIWEResult)
    case pairingCreated(WalletPairingURI)
    case pairingUpdated(WalletPairing)
    case walletEvent(WalletSessionEvent)
    case signing(WalletSignResult)

    public var id: String {
        switch self {
        case .approved(let session):
            "approved.\(session.id.rawValue)"
        case .rejected(let failure):
            "rejected.\(failure.code.map(String.init) ?? failure.message)"
        case .disconnected(let topic, _):
            "disconnected.\(topic.rawValue)"
        case .expired(let session):
            "expired.\(session.id.rawValue)"
        case .updated(let session):
            "updated.\(session.id.rawValue)"
        case .auth(let result):
            "auth.\(result.id)"
        case .siwe(let result):
            "siwe.\(result.id.uuidString)"
        case .pairingCreated(let pairingURI):
            "pairing-created.\(pairingURI.topic.rawValue)"
        case .pairingUpdated(let pairing):
            "pairing-updated.\(pairing.topic.rawValue)"
        case .walletEvent(let event):
            "event.\(event.id.uuidString)"
        case .signing(let result):
            "signing.\(result.id.rawValue)"
        }
    }
}
