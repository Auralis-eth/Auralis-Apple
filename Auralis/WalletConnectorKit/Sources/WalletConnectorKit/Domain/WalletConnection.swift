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

    public init(
        id: WalletSessionID,
        topic: WalletPairingTopic,
        providerID: String,
        providerName: String,
        accounts: [WalletAccount],
        namespaces: [WalletSessionNamespace],
        expiryDate: Date
    ) {
        self.id = id
        self.topic = topic
        self.providerID = providerID
        self.providerName = providerName
        self.accounts = accounts
        self.namespaces = namespaces
        self.expiryDate = expiryDate
    }

    public var isExpired: Bool {
        expiryDate <= Date()
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
    public let pairingURI: WalletConnectURI
    public let walletOpenURL: URL?
    public let qrPayload: String

    public init(pairingURI: WalletConnectURI, walletOpenURL: URL? = nil, qrPayload: String) {
        self.pairingURI = pairingURI
        self.walletOpenURL = walletOpenURL
        self.qrPayload = qrPayload
    }
}

public enum WalletConnectorEvent: Hashable, Sendable {
    case pairingCreated(WalletConnectURI)
    case sessionSettled(WalletConnectorSession)
    case sessionRejected(WalletConnectionError)
    case sessionDeleted(WalletSessionID)
    case requestExpired(WalletSignRequestID)
    case responseReceived(WalletResponse)
    case socketStatusChanged(WalletSocketStatus)
}

public protocol WalletConnector: Sendable {
    var events: AsyncStream<WalletConnectorEvent> { get }

    func connect(
        proposal: WalletNamespaceProposalSet,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart
    func handleCallback(url: URL) async throws
    func sessions() async throws -> [WalletConnectorSession]
    func disconnect(sessionId: WalletSessionID) async throws
    func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse
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
