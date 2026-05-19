import Foundation

public struct NFTIdentity: Hashable, Codable, Sendable {
    public let account: AuralisEthereumAddress
    public let chain: Chain
    public let contract: AuralisEthereumAddress?
    public let tokenID: String

    public init(
        account: AuralisEthereumAddress,
        chain: Chain,
        contract: AuralisEthereumAddress?,
        tokenID: String
    ) {
        self.account = account
        self.chain = chain
        self.contract = contract
        self.tokenID = tokenID
    }
}

public struct NFTMetadataSnapshot: Hashable, Codable, Sendable {
    public let identity: NFTIdentity
    public let tokenType: String?
    public let name: String?
    public let description: String?
    public let imageURLString: String?
    public let animationURLString: String?
    public let audioURLString: String?
    public let collectionName: String?
    public let artistName: String?

    public init(
        identity: NFTIdentity,
        tokenType: String?,
        name: String?,
        description: String?,
        imageURLString: String?,
        animationURLString: String?,
        audioURLString: String?,
        collectionName: String?,
        artistName: String?
    ) {
        self.identity = identity
        self.tokenType = tokenType
        self.name = name
        self.description = description
        self.imageURLString = imageURLString
        self.animationURLString = animationURLString
        self.audioURLString = audioURLString
        self.collectionName = collectionName
        self.artistName = artistName
    }
}

public struct AccountSummary: Hashable, Codable, Sendable {
    public let address: AuralisEthereumAddress
    public let name: String?
    public let source: EOAccountSource
    public let preferredChain: Chain
    public let currentChain: Chain

    public init(
        address: AuralisEthereumAddress,
        name: String?,
        source: EOAccountSource,
        preferredChain: Chain,
        currentChain: Chain
    ) {
        self.address = address
        self.name = name
        self.source = source
        self.preferredChain = preferredChain
        self.currentChain = currentChain
    }
}

public struct TokenHoldingDescriptor: Hashable, Codable, Sendable {
    public let accountAddress: AuralisEthereumAddress
    public let chain: Chain
    public let contractAddress: AuralisEthereumAddress?
    public let symbol: String?
    public let displayName: String
    public let amountDisplay: String
    public let kindRawValue: String

    public init(
        accountAddress: AuralisEthereumAddress,
        chain: Chain,
        contractAddress: AuralisEthereumAddress?,
        symbol: String?,
        displayName: String,
        amountDisplay: String,
        kindRawValue: String
    ) {
        self.accountAddress = accountAddress
        self.chain = chain
        self.contractAddress = contractAddress
        self.symbol = symbol
        self.displayName = displayName
        self.amountDisplay = amountDisplay
        self.kindRawValue = kindRawValue
    }
}

public struct PlaylistDescriptor: Hashable, Codable, Sendable {
    public let id: UUID
    public let title: String
    public let description: String?
    public let imageRef: String?

    public init(id: UUID, title: String, description: String?, imageRef: String?) {
        self.id = id
        self.title = title
        self.description = description
        self.imageRef = imageRef
    }
}

public struct SearchHistoryValue: Hashable, Codable, Sendable {
    public let accountAddressRawValue: String?
    public let normalizedQuery: String
    public let query: String
    public let recordedAt: Date

    public init(
        accountAddressRawValue: String?,
        normalizedQuery: String,
        query: String,
        recordedAt: Date
    ) {
        self.accountAddressRawValue = accountAddressRawValue
        self.normalizedQuery = normalizedQuery
        self.query = query
        self.recordedAt = recordedAt
    }
}
