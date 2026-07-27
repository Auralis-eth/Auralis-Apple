import AuralisPrimaryModels
import Foundation

/// One distinct collection (contract + chain) in the scoped library.
public struct LibraryCollectionGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let collectionName: String
    public let contractAddress: String?
    public let chain: Chain
    public let itemCount: Int
    public let artworkURLStrings: [String]

    public init(
        id: String,
        collectionName: String,
        contractAddress: String?,
        chain: Chain,
        itemCount: Int,
        artworkURLStrings: [String]
    ) {
        self.id = id
        self.collectionName = collectionName
        self.contractAddress = contractAddress
        self.chain = chain
        self.itemCount = itemCount
        self.artworkURLStrings = artworkURLStrings
    }
}

/// One distinct creator identity (never merged by display name alone).
public struct LibraryCreatorGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let itemCount: Int
    public let artworkURLStrings: [String]

    public init(id: String, displayName: String, itemCount: Int, artworkURLStrings: [String]) {
        self.id = id
        self.displayName = displayName
        self.itemCount = itemCount
        self.artworkURLStrings = artworkURLStrings
    }
}

public struct AuraPlayCreatorProfile: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let items: [MediaItemQueryItem]
    public let itemCount: Int
    public let chains: [Chain]
    public let playedItemCount: Int

    public init(id: String, displayName: String, items: [MediaItemQueryItem]) {
        self.id = id
        self.displayName = displayName
        self.items = items
        self.itemCount = items.count
        self.chains = Array(Set(items.map(\.chain))).sorted { $0.routingDisplayName < $1.routingDisplayName }
        self.playedItemCount = items.filter { $0.lastPlayedAt != nil }.count
    }
}

/// Cached grouping result for one scope. Rebuilt only when the scope changes
/// or a sync generation completes, never per render.
public struct AuraPlayGroupedLibraryIndex: Equatable, Sendable {
    public let scope: AuraPlayLibraryScope
    public let collections: [LibraryCollectionGroup]
    public let creators: [LibraryCreatorGroup]

    public init(
        scope: AuraPlayLibraryScope,
        collections: [LibraryCollectionGroup],
        creators: [LibraryCreatorGroup]
    ) {
        self.scope = scope
        self.collections = collections
        self.creators = creators
    }

    public static func empty(scope: AuraPlayLibraryScope) -> AuraPlayGroupedLibraryIndex {
        AuraPlayGroupedLibraryIndex(scope: scope, collections: [], creators: [])
    }
}

public enum LibraryGroupKey: Equatable, Sendable {
    case collection(id: String)
    case creator(id: String)
}

/// Typed media query surface consumed by Library UI. Implemented by
/// `AuraPlayMediaItemService`; fakes implement it for package tests.
public protocol AuraPlayMediaItemQuerying: Sendable {
    func fetchWindow(context: MediaItemQueryContext) async throws -> MediaItemQueryResult
    func fetchGroupedIndex(scope: AuraPlayLibraryScope) async throws -> AuraPlayGroupedLibraryIndex
    func fetchGroupItems(
        scope: AuraPlayLibraryScope,
        group: LibraryGroupKey,
        sort: MediaItemSort
    ) async throws -> [MediaItemQueryItem]
    func fetchItems(scope: AuraPlayLibraryScope, ids: [String]) async throws -> [MediaItemQueryItem]
    func fetchCreatorProfile(
        creatorIdentifier: String,
        accountAddresses: [String],
        chains: Set<Chain>?,
        sort: MediaItemSort
    ) async throws -> AuraPlayCreatorProfile?
}

public extension AuraPlayMediaItemQuerying {
    func fetchCreatorProfile(
        creatorIdentifier: String,
        accountAddresses: [String],
        chains: Set<Chain>?,
        sort: MediaItemSort
    ) async throws -> AuraPlayCreatorProfile? {
        nil
    }
}
