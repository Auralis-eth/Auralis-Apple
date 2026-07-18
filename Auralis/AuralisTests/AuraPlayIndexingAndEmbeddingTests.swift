import AuralisPrimaryModels
import Foundation
import MusicFeature
import SwiftData
import Testing

@Suite("AuraPlay indexing and embedding")
struct AuraPlayIndexingAndEmbeddingTests {
    @Test("Spotlight indexer submits searchable requested media documents")
    func spotlightIndexerIndexesRequestedSearchableMedia() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(Self.mediaItem(id: "media-1", title: "Glass Track", artistName: "Aura", collectionName: "Phase 5"))
        context.insert(Self.mediaItem(id: "media-2", title: "Hidden Track", isSearchable: false))
        try context.save()
        let client = RecordingSpotlightIndexClient()
        let indexer = AuraPlaySpotlightIndexer(modelContainer: container, indexClient: client)

        let result = try await indexer.indexItemsReturningResult(["media-2", "media-1", "missing"])

        #expect(result.requestedCount == 3)
        #expect(result.indexedCount == 1)
        #expect(result.deletedCount == 2)
        let documents = client.documents()
        let document = try #require(documents.first)
        #expect(document.id == "media-1")
        #expect(document.domainIdentifier == AuraPlaySpotlightDocument.mediaDomainIdentifier)
        #expect(document.title == "Glass Track")
        #expect(document.keywords.contains("Aura"))
        #expect(document.contentDescription.contains("Audio NFT"))
        #expect(client.deletedIDs() == ["media-2", "missing"])
    }

    @Test("Spotlight indexer can explicitly delete transferred media IDs")
    func spotlightIndexerDeletesTransferredMediaIDs() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let client = RecordingSpotlightIndexClient()
        let indexer = AuraPlaySpotlightIndexer(modelContainer: container, indexClient: client)

        let result = try await indexer.deleteItemsReturningResult(["media-3", "media-1", "media-3"])

        #expect(result.requestedCount == 2)
        #expect(result.deletedCount == 2)
        #expect(client.deletedIDs() == ["media-1", "media-3"])
    }

    @Test("embedding service persists vectors and respects the processing limit")
    func embeddingServicePersistsVectorsWithLimit() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(Self.mediaItem(id: "media-1", title: "First Track"))
        context.insert(Self.mediaItem(id: "media-2", title: "Second Track"))
        try context.save()
        let provider = FixedEmbeddingProvider(vector: [1, 2, 3])
        let service = AuraPlayEmbeddingService(modelContainer: container, embeddingProvider: provider)

        let result = try await service.processQueueReturningResult(limit: 1)

        #expect(result.scannedCount == 2)
        #expect(result.processedCount == 1)
        let embeddings = try context.fetch(FetchDescriptor<AuraPlayMediaEmbedding>())
        #expect(embeddings.count == 1)
        let vectorData = try #require(embeddings.first?.vectorData)
        #expect(AuraPlayEmbeddingVectorCodec.vector(from: vectorData) == [1, 2, 3])
        #expect(provider.requests().count == 1)
    }

    @Test("embedding service skips unchanged rows for the same model version")
    func embeddingServiceSkipsUnchangedRows() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(Self.mediaItem(id: "media-1", title: "Stable Track"))
        try context.save()
        let provider = FixedEmbeddingProvider(vector: [4, 5])
        let service = AuraPlayEmbeddingService(modelContainer: container, embeddingProvider: provider)

        let first = try await service.processQueueReturningResult(limit: 10)
        let second = try await service.processQueueReturningResult(limit: 10)

        #expect(first.processedCount == 1)
        #expect(second.processedCount == 0)
        #expect(second.skippedCount == 1)
        #expect(provider.requests().count == 1)
    }

    @Test("semantic search ranks matching vectors inside the active wallet scope")
    func semanticSearchRanksScopedVectorMatches() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(Self.mediaItem(id: "media-1", title: "Late Night Synth", artistName: "Aura", collectionName: "Nocturne"))
        context.insert(Self.mediaItem(id: "media-2", title: "Bright Morning", artistName: "Aura", collectionName: "Dawn"))
        context.insert(
            Self.mediaItem(
                id: "media-3",
                title: "Other Wallet Synth",
                artistName: "Other",
                collectionName: "Nocturne",
                accountAddressRawValue: "0x999"
            )
        )
        context.insert(
            AuraPlayMediaEmbedding(
                mediaItemID: "media-1",
                vectorData: AuraPlayEmbeddingVectorCodec.data(from: [1, 0]),
                embeddingModelVersion: "fixed-test-v1",
                sourceFingerprint: "media-1"
            )
        )
        context.insert(
            AuraPlayMediaEmbedding(
                mediaItemID: "media-2",
                vectorData: AuraPlayEmbeddingVectorCodec.data(from: [0, 1]),
                embeddingModelVersion: "fixed-test-v1",
                sourceFingerprint: "media-2"
            )
        )
        context.insert(
            AuraPlayMediaEmbedding(
                mediaItemID: "media-3",
                vectorData: AuraPlayEmbeddingVectorCodec.data(from: [1, 0]),
                embeddingModelVersion: "fixed-test-v1",
                sourceFingerprint: "media-3"
            )
        )
        try context.save()
        let provider = FixedEmbeddingProvider(vector: [1, 0])
        let service = AuraPlayEmbeddingService(modelContainer: container, embeddingProvider: provider)

        let results = try await service.search(
            query: "night synth",
            in: AuraPlayLibraryScope(accountAddress: "0x123", chain: .ethMainnet),
            limit: 5,
            minimumScore: 0.5
        )

        #expect(results.map(\.id) == ["media-1"])
        #expect(results.first?.title == "Late Night Synth")
        #expect(results.first?.isPlayable == true)
        #expect(provider.requests() == ["night synth"])
    }

    @Test("semantic search returns empty results for blank queries and zero vectors")
    func semanticSearchHandlesEmptyOrInvalidQueries() async throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)
        let provider = FixedEmbeddingProvider(vector: [])
        let service = AuraPlayEmbeddingService(modelContainer: container, embeddingProvider: provider)

        let blankResults = try await service.search(
            query: "   ",
            in: AuraPlayLibraryScope(accountAddress: "0x123", chain: .ethMainnet),
            limit: 5,
            minimumScore: 0
        )
        let invalidResults = try await service.search(
            query: "silent",
            in: AuraPlayLibraryScope(accountAddress: "0x123", chain: .ethMainnet),
            limit: 5,
            minimumScore: 0
        )

        #expect(blankResults.isEmpty)
        #expect(invalidResults.isEmpty)
        #expect(provider.requests() == ["silent"])
    }

    private static func mediaItem(
        id: String,
        title: String,
        artistName: String? = "Artist",
        collectionName: String? = "Collection",
        accountAddressRawValue: String = "0x123",
        isSearchable: Bool = true,
        updatedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> AuraPlayMediaItem {
        AuraPlayMediaItem(
            sourceNFTID: id,
            accountAddressRawValue: accountAddressRawValue,
            chain: .ethMainnet,
            contractAddressRawValue: "0xcontract",
            tokenID: id,
            tokenType: "ERC721",
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: title.lowercased(),
            normalizedArtistKey: artistName?.lowercased() ?? "",
            normalizedCollectionKey: collectionName?.lowercased() ?? "",
            artworkURLString: "https://example.com/\(id).png",
            playbackURLString: "https://example.com/\(id).mp3",
            contentType: "mp3",
            sourceUpdatedAtRawValue: nil,
            hasArtwork: true,
            hasAudio: true,
            hasVideo: false,
            isPlayable: true,
            isSearchable: isSearchable,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}

private final class RecordingSpotlightIndexClient: AuraPlaySpotlightIndexClient, @unchecked Sendable {
    private let lock = NSLock()
    private var indexedDocuments: [AuraPlaySpotlightDocument] = []
    private var deletedIDValues: [String] = []

    func index(_ documents: [AuraPlaySpotlightDocument]) async throws {
        lock.withLock {
            indexedDocuments.append(contentsOf: documents)
        }
    }

    func delete(ids: [String]) async throws {
        lock.withLock {
            deletedIDValues.append(contentsOf: ids)
        }
    }

    func documents() -> [AuraPlaySpotlightDocument] {
        lock.withLock { indexedDocuments }
    }

    func deletedIDs() -> [String] {
        lock.withLock { deletedIDValues }
    }
}

private final class FixedEmbeddingProvider: TextEmbeddingProviding, @unchecked Sendable {
    let modelVersion = "fixed-test-v1"
    private let vector: [Float]
    private let lock = NSLock()
    private var requestedTexts: [String] = []

    init(vector: [Float]) {
        self.vector = vector
    }

    func vector(for text: String) -> [Float]? {
        lock.withLock {
            requestedTexts.append(text)
        }
        return vector
    }

    func requests() -> [String] {
        lock.withLock { requestedTexts }
    }
}
