import Foundation
@testable import MusicFeature
import SwiftData
import Testing

struct AuraPlaySemanticSearchQualityTests {
    struct RelevanceCase: Sendable {
        let query: String
        let queryVector: [Float]
        let expectedIDs: [String]
    }

    @Test(
        "Representative queries rank deterministic semantic fixtures",
        arguments: [
            RelevanceCase(
                query: "dreamy night drive",
                queryVector: [1, 0, 0],
                expectedIDs: ["nft-00000", "nft-00007"]
            ),
            RelevanceCase(
                query: "dark volcanic beat",
                queryVector: [0, 1, 0],
                expectedIDs: ["nft-00001", "nft-00002"]
            ),
            RelevanceCase(
                query: "bright meadow video",
                queryVector: [0, 0, 1],
                expectedIDs: ["nft-00003", "nft-00004"]
            )
        ]
    )
    @MainActor
    func representativeQueriesRankExpectedItems(testCase: RelevanceCase) async throws {
        let container = try AuraPlayLibrarySeed.makeContainer()
        try AuraPlayLibrarySeed.seed(container, tier: .standard)
        let context = ModelContext(container)
        let vectors: [String: [Float]] = [
            "nft-00000": [1, 0, 0],
            "nft-00007": [0.92, 0.08, 0],
            "nft-00001": [0, 1, 0],
            "nft-00002": [0.05, 0.95, 0],
            "nft-00003": [0, 0, 1],
            "nft-00004": [0.05, 0.05, 0.9],
            "nft-00005": [0.34, 0.33, 0.33]
        ]
        for (mediaID, vector) in vectors {
            context.insert(
                AuraPlayMediaEmbedding(
                    mediaItemID: mediaID,
                    vectorData: AuraPlayEmbeddingVectorCodec.data(from: vector),
                    embeddingModelVersion: DeterministicQueryEmbeddingProvider.modelVersion,
                    sourceFingerprint: mediaID,
                    indexedAt: AuraPlayLibrarySeed.baseDate
                )
            )
        }
        try context.save()
        let provider = DeterministicQueryEmbeddingProvider(vectors: [testCase.query: testCase.queryVector])
        let service = AuraPlayEmbeddingService(modelContainer: container, embeddingProvider: provider)

        let results = try await service.search(
            query: testCase.query,
            in: AuraPlayLibrarySeed.scope,
            limit: 2,
            minimumScore: 0.5
        )

        #expect(results.map(\.id) == testCase.expectedIDs)
        #expect(results.allSatisfy { $0.score >= 0.5 })
    }

    @Test("The relevance fixture is independent of NaturalLanguage model availability")
    func missingFixtureQueryReturnsNoVector() {
        let provider = DeterministicQueryEmbeddingProvider(vectors: ["known": [1, 0]])

        #expect(provider.vector(for: "unknown") == nil)
    }
}

private struct DeterministicQueryEmbeddingProvider: TextEmbeddingProviding {
    static let modelVersion = "semantic-quality-fixture-v1"

    let vectors: [String: [Float]]
    var modelVersion: String { Self.modelVersion }

    func vector(for text: String) -> [Float]? {
        vectors[text]
    }
}
