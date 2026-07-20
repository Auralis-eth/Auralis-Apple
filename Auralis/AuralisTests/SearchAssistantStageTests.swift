@testable import Auralis
import Testing

#if canImport(CoreSpotlight)
@preconcurrency import CoreSpotlight
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// These suites exercise the iOS 27-only assistant pipeline stages at the unit level.
// The stages accept plain `[CSSearchableItem]`, so they can be tested without the
// on-device language model. On pre-iOS-27 runtimes the guards make the tests no-ops;
// they lock in the structured-token contract for when an iOS 27 lane exists.
#if canImport(FoundationModels) && canImport(CoreSpotlight)
import FoundationModels

@available(iOS 27.0, *)
private func makeItem(
    id: String,
    domain: String,
    keywordTokens: [(String, String)],
    extraKeywords: [String] = []
) -> CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .data)
    let structured = keywordTokens.compactMap { SearchSpotlightMetadataToken.token($0.0, $0.1) }
    attributes.keywords = structured + extraKeywords
    return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain, attributeSet: attributes)
}

@available(iOS 27.0, *)
private func scoredItems(from data: SearchPipelineData) -> [(id: String, score: Double)]? {
    guard case .scoredItems(let items) = data.payload else {
        return nil
    }
    return items.map { (id: $0.item.uniqueIdentifier, score: $0.score) }
}

struct SearchAssistantMediaCapabilityStageTests {
    @Test("audio playable items score above non-playable visual items and filter by threshold")
    func scoresAndFiltersByStructuredTokens() async throws {
        guard #available(iOS 27.0, *) else { return }

        let items = [
            makeItem(
                id: "audio-1",
                domain: SearchIndexedDocument.Domain.nft.rawValue,
                keywordTokens: [("mediaKind", "audio"), ("isPlayable", "true"), ("artistName", "Nova")]
            ),
            makeItem(
                id: "visual-1",
                domain: SearchIndexedDocument.Domain.nft.rawValue,
                keywordTokens: [("mediaKind", "visual"), ("isPlayable", "false")]
            ),
        ]

        let stage = AuralisMediaCapabilityStage(preferredMediaKind: nil, threshold: nil)
        let result = try await stage.execute(items: items)
        let scored = try #require(scoredItems(from: result))

        // Visual non-playable item scores 0 and is dropped by the default threshold.
        #expect(scored.count == 1)
        let audio = try #require(scored.first)
        #expect(audio.id == "audio-1")
        // audio (0.35) + playable (0.25) + attribution (0.15) = 0.75
        #expect(abs(audio.score - 0.75) < 0.0001)
    }

    @Test("preferred media kind synonyms boost matching items")
    func preferredKindSynonymBoostsScore() async throws {
        guard #available(iOS 27.0, *) else { return }

        let items = [
            makeItem(
                id: "audio-1",
                domain: SearchIndexedDocument.Domain.nft.rawValue,
                keywordTokens: [("mediaKind", "audio"), ("isPlayable", "true"), ("artistName", "Nova")]
            )
        ]

        // "music" should canonicalize to "audio" and add the preference weight.
        let stage = AuralisMediaCapabilityStage(preferredMediaKind: "music", threshold: nil)
        let result = try await stage.execute(items: items)
        let scored = try #require(scoredItems(from: result))
        let audio = try #require(scored.first)
        // 0.75 + preference (0.35) capped at 1.0
        #expect(abs(audio.score - 1.0) < 0.0001)
    }

    @Test("no substring fallback: music mentioned only in free text is ignored")
    func ignoresUnstructuredText() async throws {
        guard #available(iOS 27.0, *) else { return }

        // No structured media tokens, but "music" appears in loose keywords. The
        // hardened stage relies on structured tokens only, so this scores 0.
        let item = makeItem(
            id: "loose-1",
            domain: SearchIndexedDocument.Domain.nft.rawValue,
            keywordTokens: [],
            extraKeywords: ["music", "audio", "playable"]
        )

        let stage = AuralisMediaCapabilityStage(preferredMediaKind: nil, threshold: nil)
        let result = try await stage.execute(items: [item])
        let scored = try #require(scoredItems(from: result))
        #expect(scored.isEmpty)
    }

    @Test("media kind synonyms map onto canonical indexed values")
    func canonicalMediaKindMapping() {
        guard #available(iOS 27.0, *) else { return }

        #expect(AuralisMediaCapabilityStage.canonicalMediaKind(from: "Songs") == "audio")
        #expect(AuralisMediaCapabilityStage.canonicalMediaKind(from: "movie") == "video")
        #expect(AuralisMediaCapabilityStage.canonicalMediaKind(from: "artwork") == "visual")
        #expect(AuralisMediaCapabilityStage.canonicalMediaKind(from: "playable") == "playable")
        #expect(AuralisMediaCapabilityStage.canonicalMediaKind(from: "   ") == nil)
        #expect(AuralisMediaCapabilityStage.canonicalMediaKind(from: nil) == nil)
    }
}

struct SearchAssistantReceiptRollupStageTests {
    @Test("groups receipts by status from structured tokens, ordered by count")
    func groupsByStatus() async throws {
        guard #available(iOS 27.0, *) else { return }

        let items = [
            makeItem(id: "r1", domain: SearchIndexedDocument.Domain.receipt.rawValue, keywordTokens: [("receiptStatus", "Failed")]),
            makeItem(id: "r2", domain: SearchIndexedDocument.Domain.receipt.rawValue, keywordTokens: [("receiptStatus", "Failed")]),
            makeItem(id: "r3", domain: SearchIndexedDocument.Domain.receipt.rawValue, keywordTokens: [("receiptStatus", "Succeeded")]),
        ]

        let stage = AuralisReceiptRollupStage(groupBy: nil)
        let result = try await stage.execute(items: items)
        guard case .table(let table) = result.payload else {
            Issue.record("Expected a table payload")
            return
        }

        #expect(table.rows.count == 2)
        // Highest count first: Failed (2) then Succeeded (1).
        let firstRow = try #require(table.rows.first)
        #expect(SearchAssistantPayload.cellString(for: firstRow.values[0]) == "Failed")
        #expect(SearchAssistantPayload.cellString(for: firstRow.values[1]) == "2")
    }

    @Test("chain grouping reads the shared chain token (regression for receiptChain bug)")
    func groupsByChainToken() async throws {
        guard #available(iOS 27.0, *) else { return }

        let items = [
            makeItem(id: "r1", domain: SearchIndexedDocument.Domain.receipt.rawValue, keywordTokens: [("chain", "Ethereum")]),
            makeItem(id: "r2", domain: SearchIndexedDocument.Domain.receipt.rawValue, keywordTokens: [("chain", "Ethereum")]),
            makeItem(id: "r3", domain: SearchIndexedDocument.Domain.receipt.rawValue, keywordTokens: [("chain", "Base")]),
        ]

        let stage = AuralisReceiptRollupStage(groupBy: "chain")
        let result = try await stage.execute(items: items)
        guard case .table(let table) = result.payload else {
            Issue.record("Expected a table payload")
            return
        }

        // Previously chain grouping looked up a non-existent `receiptChain` token and
        // fell back to fragile free-text parsing. It now resolves via the `chain` token.
        #expect(table.rows.count == 2)
        let firstRow = try #require(table.rows.first)
        #expect(SearchAssistantPayload.cellString(for: firstRow.values[0]) == "Ethereum")
        #expect(SearchAssistantPayload.cellString(for: firstRow.values[1]) == "2")
    }

    @Test("no receipt items returns a zero count rather than an empty table")
    func noReceiptsReturnsCount() async throws {
        guard #available(iOS 27.0, *) else { return }

        let items = [
            makeItem(id: "n1", domain: SearchIndexedDocument.Domain.nft.rawValue, keywordTokens: [("mediaKind", "audio")])
        ]

        let stage = AuralisReceiptRollupStage(groupBy: nil)
        let result = try await stage.execute(items: items)
        if case .count = result.payload {
            // Expected: a zero count rather than a table when no receipts match.
        } else {
            Issue.record("Expected a count payload")
        }
    }
}

struct SearchAssistantTableCellTests {
    @Test("typed table cells format without leaking enum syntax")
    func formatsTypedCells() {
        guard #available(iOS 27.0, *) else { return }

        #expect(SearchAssistantPayload.cellString(for: .string("Failed")) == "Failed")
        #expect(SearchAssistantPayload.cellString(for: .integer(3)) == "3")
        #expect(SearchAssistantPayload.cellString(for: .boolean(true)) == "Yes")
        #expect(SearchAssistantPayload.cellString(for: .boolean(false)) == "No")
        #expect(SearchAssistantPayload.cellString(for: .none) == "")
    }
}
#endif
