import Foundation

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

public enum WalletConnectionError: Error, Equatable, Sendable {
    case unsupportedProvider(WalletProviderID)
    case unsupportedChain(WalletChain)
    case unavailable(String)
    case cancelled
}

public protocol WalletConnector: Sendable {
    var provider: ThirdPartyWalletProvider { get }

    func connect(request: WalletConnectionRequest) async throws -> WalletConnectionSession
    func disconnect(session: WalletConnectionSession) async
}
