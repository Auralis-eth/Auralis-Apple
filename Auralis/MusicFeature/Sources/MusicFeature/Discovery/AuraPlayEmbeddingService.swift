import Foundation
import NaturalLanguage
import SwiftData

public protocol TextEmbeddingProviding: Sendable {
    var modelVersion: String { get }
    func vector(for text: String) -> [Float]?
}

public struct NaturalLanguageTextEmbeddingProvider: TextEmbeddingProviding {
    public let modelVersion: String

    public init(modelVersion: String = Self.defaultModelVersion) {
        self.modelVersion = modelVersion
    }

    public func vector(for text: String) -> [Float]? {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return nil }

        if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english),
           let vector = sentenceEmbedding.vector(for: cleanedText) {
            return vector.map(Float.init)
        }

        guard let wordEmbedding = NLEmbedding.wordEmbedding(for: .english) else {
            return nil
        }

        let vectors = cleanedText
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap { wordEmbedding.vector(for: String($0).lowercased()) }
        guard let firstVector = vectors.first else { return nil }

        var average = Array(repeating: 0.0, count: firstVector.count)
        for vector in vectors {
            for index in vector.indices {
                average[index] += vector[index]
            }
        }

        return average.map { Float($0 / Double(vectors.count)) }
    }

    public static var defaultModelVersion: String {
        let sentenceRevision = NLEmbedding.currentSentenceEmbeddingRevision(for: .english)
        let wordRevision = NLEmbedding.currentRevision(for: .english)
        return "natural-language:en:sentence-\(sentenceRevision):word-\(wordRevision)"
    }
}

public struct AuraPlayEmbeddingProcessResult: Equatable, Sendable {
    public let scannedCount: Int
    public let processedCount: Int
    public let skippedCount: Int

    public init(scannedCount: Int, processedCount: Int, skippedCount: Int) {
        self.scannedCount = scannedCount
        self.processedCount = processedCount
        self.skippedCount = skippedCount
    }
}

public struct AuraPlaySemanticSearchResult: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let artistName: String?
    public let collectionName: String?
    public let artworkURLString: String?
    public let playbackURLString: String?
    public let isPlayable: Bool
    public let score: Float

    public init(
        id: String,
        title: String,
        artistName: String?,
        collectionName: String?,
        artworkURLString: String?,
        playbackURLString: String?,
        isPlayable: Bool,
        score: Float
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.collectionName = collectionName
        self.artworkURLString = artworkURLString
        self.playbackURLString = playbackURLString
        self.isPlayable = isPlayable
        self.score = score
    }
}

public actor AuraPlayEmbeddingService: EmbeddingQueueProcessing, AuraPlaySemanticSearching {
    private let modelContainer: ModelContainer
    private let embeddingProvider: any TextEmbeddingProviding
    private let clock: @Sendable () -> Date

    public init(
        modelContainer: ModelContainer,
        embeddingProvider: any TextEmbeddingProviding = NaturalLanguageTextEmbeddingProvider(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.modelContainer = modelContainer
        self.embeddingProvider = embeddingProvider
        self.clock = clock
    }

    public func processQueue(limit: Int) async {
        do {
            _ = try processQueueReturningResult(limit: limit)
        } catch { }
    }

    @discardableResult
    public func processQueueReturningResult(limit: Int) throws -> AuraPlayEmbeddingProcessResult {
        guard limit > 0 else {
            return AuraPlayEmbeddingProcessResult(scannedCount: 0, processedCount: 0, skippedCount: 0)
        }

        let modelContext = ModelContext(modelContainer)
        let items = try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaItem>(
                predicate: #Predicate<AuraPlayMediaItem> { item in
                    item.isSearchable
                },
                sortBy: [SortDescriptor(\.updatedAt), SortDescriptor(\.sourceNFTID)]
            )
        )
        // Fetch only the embeddings for the searchable items under
        // consideration instead of the entire embedding table.
        let searchableIDs = items.map(\.sourceNFTID)
        let embeddings = try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaEmbedding>(
                predicate: #Predicate<AuraPlayMediaEmbedding> { embedding in
                    searchableIDs.contains(embedding.mediaItemID)
                }
            )
        )
        var embeddingsByMediaID = Dictionary(
            embeddings.map { ($0.mediaItemID, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        var processedCount = 0
        var skippedCount = 0

        for item in items {
            guard processedCount < limit else { break }

            let fingerprint = AuraPlayEmbeddingText.fingerprint(for: item)
            let existing = embeddingsByMediaID[item.sourceNFTID]
            if existing?.embeddingModelVersion == embeddingProvider.modelVersion,
               existing?.sourceFingerprint == fingerprint,
               existing?.vectorData != nil {
                skippedCount += 1
                continue
            }

            guard let vector = embeddingProvider.vector(for: AuraPlayEmbeddingText.text(for: item)) else {
                skippedCount += 1
                continue
            }

            let vectorData = AuraPlayEmbeddingVectorCodec.data(from: vector)
            if let existing {
                existing.vectorData = vectorData
                existing.embeddingModelVersion = embeddingProvider.modelVersion
                existing.sourceFingerprint = fingerprint
                existing.indexedAt = clock()
            } else {
                let embedding = AuraPlayMediaEmbedding(
                    mediaItemID: item.sourceNFTID,
                    vectorData: vectorData,
                    embeddingModelVersion: embeddingProvider.modelVersion,
                    sourceFingerprint: fingerprint,
                    indexedAt: clock()
                )
                modelContext.insert(embedding)
                embeddingsByMediaID[item.sourceNFTID] = embedding
            }
            processedCount += 1
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }

        return AuraPlayEmbeddingProcessResult(
            scannedCount: items.count,
            processedCount: processedCount,
            skippedCount: skippedCount
        )
    }

    public func search(
        query: String,
        in scope: AuraPlayLibraryScope,
        limit: Int = 12,
        minimumScore: Float = 0.18
    ) async throws -> [AuraPlaySemanticSearchResult] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !cleanedQuery.isEmpty, let queryVector = embeddingProvider.vector(for: cleanedQuery) else {
            return []
        }

        let normalizedAccountAddress = NFTTokenDTO.normalizedScopeComponent(scope.accountAddress) ?? ""
        let chainRawValue = scope.chain.rawValue
        let modelContext = ModelContext(modelContainer)
        let items = try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaItem>(
                predicate: #Predicate<AuraPlayMediaItem> { item in
                    item.isSearchable
                        && item.accountAddressRawValue == normalizedAccountAddress
                        && item.chainRawValue == chainRawValue
                }
            )
        )
        let modelVersion = embeddingProvider.modelVersion
        let embeddings = try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaEmbedding>(
                predicate: #Predicate<AuraPlayMediaEmbedding> { embedding in
                    embedding.embeddingModelVersion == modelVersion
                }
            )
        )
        let embeddingsByMediaID = Dictionary(uniqueKeysWithValues: embeddings.map { ($0.mediaItemID, $0) })

        var matches: [AuraPlaySemanticSearchResult] = []
        for item in items {
            try Task.checkCancellation()
            guard let embedding = embeddingsByMediaID[item.sourceNFTID],
                  let vectorData = embedding.vectorData,
                  let score = Self.cosineSimilarity(queryVector, AuraPlayEmbeddingVectorCodec.vector(from: vectorData)),
                  score >= minimumScore else {
                continue
            }

            matches.append(
                AuraPlaySemanticSearchResult(
                    id: item.sourceNFTID,
                    title: item.title,
                    artistName: item.artistName,
                    collectionName: item.collectionName,
                    artworkURLString: item.artworkURLString,
                    playbackURLString: item.playbackURLString,
                    isPlayable: item.isPlayable && item.playbackURLString?.isEmpty == false,
                    score: score
                )
            )
        }

        return matches
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float? {
        guard !lhs.isEmpty, lhs.count == rhs.count else { return nil }

        var dotProduct: Float = 0
        var lhsMagnitude: Float = 0
        var rhsMagnitude: Float = 0
        for index in lhs.indices {
            dotProduct += lhs[index] * rhs[index]
            lhsMagnitude += lhs[index] * lhs[index]
            rhsMagnitude += rhs[index] * rhs[index]
        }

        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return nil }
        return dotProduct / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
    }
}

public enum AuraPlayEmbeddingVectorCodec {
    public static func data(from vector: [Float]) -> Data {
        var mutableVector = vector
        return Data(bytes: &mutableVector, count: MemoryLayout<Float>.stride * mutableVector.count)
    }

    public static func vector(from data: Data) -> [Float] {
        let floatCount = data.count / MemoryLayout<Float>.stride
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Float.self).baseAddress else {
                return []
            }
            return Array(UnsafeBufferPointer(start: baseAddress, count: floatCount))
        }
    }
}

private enum AuraPlayEmbeddingText {
    static func text(for item: AuraPlayMediaItem) -> String {
        [
            cleanedText(item.title),
            cleanedText(item.artistName),
            cleanedText(item.collectionName),
            item.hasVideo ? "video" : nil,
            item.hasAudio ? "audio" : nil,
            cleanedText(item.contentType),
            cleanedText(item.chainRawValue),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    static func fingerprint(for item: AuraPlayMediaItem) -> String {
        [
            cleanedText(item.title),
            cleanedText(item.artistName),
            cleanedText(item.collectionName),
            cleanedText(item.contentType),
            item.hasAudio ? "audio" : "no-audio",
            item.hasVideo ? "video" : "no-video",
            cleanedText(item.updatedAt.timeIntervalSince1970.description),
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }

    static func cleanedText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
