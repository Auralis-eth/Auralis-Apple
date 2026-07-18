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
}
