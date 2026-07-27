import AuralisPrimaryModels
import Foundation
import SwiftData

public protocol AuraPlayRecommendationProviding: Sendable {
    func moreLikeThis(
        mediaItemID: String,
        in scope: AuraPlayLibraryScope,
        limit: Int,
        minimumScore: Float
    ) async throws -> [AuraPlayRecommendationResult]

    func hasEmbedding(mediaItemID: String) async throws -> Bool

    /// Scoped set of media IDs that currently have a stored embedding vector.
    /// UI uses this to hide "More Like This" for items without an embedding
    /// without performing a per-row async lookup inside a context menu.
    func embeddedMediaItemIDs(in scope: AuraPlayLibraryScope) async throws -> Set<String>
}

public struct AuraPlayRecommendationResult: Identifiable, Equatable, Sendable {
    public let item: MediaItemQueryItem
    public let score: Float

    public var id: String { item.sourceNFTID }

    public init(item: MediaItemQueryItem, score: Float) {
        self.item = item
        self.score = score
    }
}

public struct NoOpAuraPlayRecommendationProvider: AuraPlayRecommendationProviding {
    public init() {}

    public func moreLikeThis(
        mediaItemID: String,
        in scope: AuraPlayLibraryScope,
        limit: Int,
        minimumScore: Float
    ) async throws -> [AuraPlayRecommendationResult] {
        []
    }

    public func hasEmbedding(mediaItemID: String) async throws -> Bool {
        false
    }

    public func embeddedMediaItemIDs(in scope: AuraPlayLibraryScope) async throws -> Set<String> {
        []
    }
}

@ModelActor
public actor AuraPlayRecommendationService: AuraPlayRecommendationProviding {
    public func hasEmbedding(mediaItemID: String) throws -> Bool {
        var descriptor = FetchDescriptor<AuraPlayMediaEmbedding>(
            predicate: #Predicate<AuraPlayMediaEmbedding> { embedding in
                embedding.mediaItemID == mediaItemID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.vectorData != nil
    }

    public func embeddedMediaItemIDs(in scope: AuraPlayLibraryScope) throws -> Set<String> {
        let scopedIDs = Set(try fetchScopedItems(scope: scope).map(\.sourceNFTID))
        guard !scopedIDs.isEmpty else { return [] }
        let embeddings = try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaEmbedding>(
                predicate: #Predicate<AuraPlayMediaEmbedding> { embedding in
                    scopedIDs.contains(embedding.mediaItemID)
                }
            )
        )
        return Set(embeddings.compactMap { $0.vectorData != nil ? $0.mediaItemID : nil })
    }

    public func moreLikeThis(
        mediaItemID: String,
        in scope: AuraPlayLibraryScope,
        limit: Int = 25,
        minimumScore: Float = AuraPlayIntelligenceSettings.recommendationStrictMinimumScore
    ) throws -> [AuraPlayRecommendationResult] {
        guard limit > 0,
              let sourceEmbedding = try fetchEmbedding(mediaItemID: mediaItemID),
              let sourceData = sourceEmbedding.vectorData else {
            return []
        }

        let sourceVector = AuraPlayEmbeddingVectorCodec.vector(from: sourceData)
        let scopedItems = try fetchScopedItems(scope: scope)
        let itemIDs = Set(scopedItems.map(\.sourceNFTID))
        let embeddings = try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaEmbedding>(
                predicate: #Predicate<AuraPlayMediaEmbedding> { embedding in
                    itemIDs.contains(embedding.mediaItemID)
                }
            )
        )
        let itemsByID = Dictionary(
            scopedItems.map { ($0.sourceNFTID, MediaItemQueryItem(item: $0)) },
            uniquingKeysWith: { current, _ in current }
        )
        let strictResults = rankedResults(
            sourceMediaItemID: mediaItemID,
            sourceVector: sourceVector,
            embeddings: embeddings,
            itemsByID: itemsByID,
            minimumScore: minimumScore,
            limit: limit
        )
        if strictResults.count >= AuraPlayIntelligenceSettings.recommendationRelaxationMinimumResultCount
            || minimumScore <= AuraPlayIntelligenceSettings.recommendationRelaxedMinimumScore {
            return strictResults
        }

        return rankedResults(
            sourceMediaItemID: mediaItemID,
            sourceVector: sourceVector,
            embeddings: embeddings,
            itemsByID: itemsByID,
            minimumScore: AuraPlayIntelligenceSettings.recommendationRelaxedMinimumScore,
            limit: limit
        )
    }

    private func rankedResults(
        sourceMediaItemID mediaItemID: String,
        sourceVector: [Float],
        embeddings: [AuraPlayMediaEmbedding],
        itemsByID: [String: MediaItemQueryItem],
        minimumScore: Float,
        limit: Int
    ) -> [AuraPlayRecommendationResult] {
        return embeddings.compactMap { embedding -> AuraPlayRecommendationResult? in
            guard embedding.mediaItemID != mediaItemID,
                  let vectorData = embedding.vectorData,
                  let item = itemsByID[embedding.mediaItemID],
                  item.isPlayable,
                  let score = AuraPlayEmbeddingSimilarity.cosineSimilarity(
                    sourceVector,
                    AuraPlayEmbeddingVectorCodec.vector(from: vectorData)
                  ),
                  score >= minimumScore else {
                return nil
            }
            return AuraPlayRecommendationResult(item: item, score: score)
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }
        .prefix(limit)
        .map { $0 }
    }

    private func fetchEmbedding(mediaItemID: String) throws -> AuraPlayMediaEmbedding? {
        var descriptor = FetchDescriptor<AuraPlayMediaEmbedding>(
            predicate: #Predicate<AuraPlayMediaEmbedding> { embedding in
                embedding.mediaItemID == mediaItemID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchScopedItems(scope: AuraPlayLibraryScope) throws -> [AuraPlayMediaItem] {
        let normalizedAccount = scope.accountAddress.flatMap(NFTTokenDTO.normalizedScopeComponent)
            ?? scope.accountAddress
            ?? ""
        let chainRawValue = scope.chain.rawValue
        return try modelContext.fetch(
            FetchDescriptor<AuraPlayMediaItem>(
                predicate: #Predicate<AuraPlayMediaItem> { item in
                    item.accountAddressRawValue == normalizedAccount
                        && item.chainRawValue == chainRawValue
                        && item.isSearchable
                }
            )
        )
    }
}
