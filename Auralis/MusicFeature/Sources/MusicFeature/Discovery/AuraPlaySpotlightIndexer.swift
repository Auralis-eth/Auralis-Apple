import Foundation
import SwiftData

#if canImport(CoreSpotlight)
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
#endif

public struct AuraPlaySpotlightDocument: Equatable, Sendable {
    public static let mediaDomainIdentifier = "com.auraplay.media"

    public let id: String
    public let domainIdentifier: String
    public let title: String
    public let contentDescription: String
    public let keywords: [String]
    public let hasVideo: Bool

    public init(
        id: String,
        domainIdentifier: String = Self.mediaDomainIdentifier,
        title: String,
        contentDescription: String,
        keywords: [String],
        hasVideo: Bool
    ) {
        self.id = id
        self.domainIdentifier = domainIdentifier
        self.title = title
        self.contentDescription = contentDescription
        self.keywords = keywords
        self.hasVideo = hasVideo
    }
}

public protocol AuraPlaySpotlightIndexClient: Sendable {
    func index(_ documents: [AuraPlaySpotlightDocument]) async throws
    func delete(ids: [String]) async throws
}

public actor AuraPlaySpotlightIndexer: MediaItemIndexing {
    private let modelContainer: ModelContainer
    private let indexClient: any AuraPlaySpotlightIndexClient

    public init(
        modelContainer: ModelContainer,
        indexClient: any AuraPlaySpotlightIndexClient = CoreSpotlightAuraPlayIndexClient()
    ) {
        self.modelContainer = modelContainer
        self.indexClient = indexClient
    }

    public func indexItems(_ ids: [String]) async {
        do {
            _ = try await indexItemsReturningResult(ids)
        } catch { }
    }

    public func deleteItems(_ ids: [String]) async {
        do {
            _ = try await deleteItemsReturningResult(ids)
        } catch { }
    }

    @discardableResult
    public func indexItemsReturningResult(_ ids: [String]) async throws -> AuraPlaySpotlightIndexResult {
        let uniqueIDs = Set(ids)
        guard !uniqueIDs.isEmpty else {
            return AuraPlaySpotlightIndexResult(requestedCount: 0, indexedCount: 0, deletedCount: 0)
        }

        let context = ModelContext(modelContainer)
        let requestedIDs = Array(uniqueIDs)
        let items = try context.fetch(
            FetchDescriptor<AuraPlayMediaItem>(
                predicate: #Predicate<AuraPlayMediaItem> { item in
                    requestedIDs.contains(item.sourceNFTID) && item.isSearchable
                },
                sortBy: [SortDescriptor(\.sourceNFTID)]
            )
        )
        let documents = items.map(AuraPlaySpotlightDocument.init(mediaItem:))
        let searchableIDs = Set(documents.map(\.id))
        let staleIDs = Array(uniqueIDs.subtracting(searchableIDs)).sorted()
        try await indexClient.index(documents)
        try await indexClient.delete(ids: staleIDs)

        return AuraPlaySpotlightIndexResult(
            requestedCount: uniqueIDs.count,
            indexedCount: documents.count,
            deletedCount: staleIDs.count
        )
    }

    @discardableResult
    public func deleteItemsReturningResult(_ ids: [String]) async throws -> AuraPlaySpotlightDeleteResult {
        let uniqueIDs = Array(Set(ids)).sorted()
        guard !uniqueIDs.isEmpty else {
            return AuraPlaySpotlightDeleteResult(requestedCount: 0, deletedCount: 0)
        }

        try await indexClient.delete(ids: uniqueIDs)
        return AuraPlaySpotlightDeleteResult(requestedCount: uniqueIDs.count, deletedCount: uniqueIDs.count)
    }
}

public struct AuraPlaySpotlightIndexResult: Equatable, Sendable {
    public let requestedCount: Int
    public let indexedCount: Int
    public let deletedCount: Int

    public init(requestedCount: Int, indexedCount: Int, deletedCount: Int) {
        self.requestedCount = requestedCount
        self.indexedCount = indexedCount
        self.deletedCount = deletedCount
    }
}

public struct AuraPlaySpotlightDeleteResult: Equatable, Sendable {
    public let requestedCount: Int
    public let deletedCount: Int

    public init(requestedCount: Int, deletedCount: Int) {
        self.requestedCount = requestedCount
        self.deletedCount = deletedCount
    }
}

public actor CoreSpotlightAuraPlayIndexClient: AuraPlaySpotlightIndexClient {
    private let indexName: String

    public init(indexName: String = "AuraPlayMedia") {
        self.indexName = indexName
    }

    public func index(_ documents: [AuraPlaySpotlightDocument]) async throws {
        guard !documents.isEmpty else { return }

        #if canImport(CoreSpotlight)
        let searchableItems = documents.map(makeSearchableItem)
        let index = CSSearchableIndex(name: indexName)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.indexSearchableItems(searchableItems) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #endif
    }

    public func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }

        #if canImport(CoreSpotlight)
        let index = CSSearchableIndex(name: indexName)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withIdentifiers: ids) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #endif
    }
}

private extension AuraPlaySpotlightDocument {
    init(mediaItem: AuraPlayMediaItem) {
        let keywordCandidates = [
            mediaItem.title,
            mediaItem.artistName,
            mediaItem.collectionName,
            mediaItem.chainRawValue,
            mediaItem.tokenType,
            mediaItem.contentType,
        ]

        self.init(
            id: mediaItem.sourceNFTID,
            title: mediaItem.title,
            contentDescription: Self.contentDescription(for: mediaItem),
            keywords: keywordCandidates.compactMap(Self.cleanedText),
            hasVideo: mediaItem.hasVideo
        )
    }

    static func contentDescription(for item: AuraPlayMediaItem) -> String {
        [
            cleanedText(item.artistName).map { "Artist: \($0)" },
            cleanedText(item.collectionName).map { "Collection: \($0)" },
            item.hasVideo ? "Video NFT" : nil,
            item.hasAudio ? "Audio NFT" : nil,
            cleanedText(item.chainRawValue).map { "Chain: \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }

    static func cleanedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if canImport(CoreSpotlight)
private extension CoreSpotlightAuraPlayIndexClient {
    func makeSearchableItem(from document: AuraPlaySpotlightDocument) -> CSSearchableItem {
        let contentType: UTType = document.hasVideo ? .movie : .audio
        let attributeSet = CSSearchableItemAttributeSet(contentType: contentType)
        attributeSet.title = document.title
        attributeSet.displayName = document.title
        attributeSet.contentDescription = document.contentDescription
        attributeSet.keywords = document.keywords

        let item = CSSearchableItem(
            uniqueIdentifier: document.id,
            domainIdentifier: document.domainIdentifier,
            attributeSet: attributeSet
        )
        item.expirationDate = .distantFuture
        return item
    }
}
#endif
