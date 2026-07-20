@testable import Auralis
import AuralisPrimaryModels
import Testing

#if canImport(CoreSpotlight)
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SearchSpotlightSupportTests {
    @Test("search identifiers round-trip domain and source id")
    func searchIdentifierRoundTrips() throws {
        let document = SearchIndexedDocument(
            id: "eth-mainnet:0xabc:moonpunks",
            domain: .collection,
            title: "Moonpunks",
            subtitle: "Ethereum",
            contentDescription: "NFT collection: Moonpunks",
            keywords: ["Moonpunks", "NFT"],
            createdAt: nil,
            modifiedAt: nil,
            destination: .nftCollection(contractAddress: "0xabc", title: "Moonpunks", chain: .ethMainnet)
        )

        let parsed = try #require(SearchIndexedDocument.parseSearchableIdentifier(document.searchableIdentifier))
        #expect(parsed.domain == .collection)
        #expect(parsed.id == "eth-mainnet:0xabc:moonpunks")
    }

    #if canImport(CoreSpotlight)
    @Test("prefixed searchable items map back to tappable app destinations")
    func prefixedSearchableItemMapsToDestination() throws {
        let document = SearchIndexedDocument(
            id: "11111111-1111-1111-1111-111111111111",
            domain: .receipt,
            title: "Context Built",
            subtitle: "Receipt summary",
            contentDescription: "Receipt event. Payload: full text",
            keywords: ["receipt", "context"],
            createdAt: nil,
            modifiedAt: nil,
            destination: .receipt(id: "11111111-1111-1111-1111-111111111111")
        )

        let match = try #require(SearchLocalMatch(searchableItem: document.searchableItem))
        #expect(match.kind == .receipt)
        #expect(match.destination == .receipt(id: "11111111-1111-1111-1111-111111111111"))
    }

    @Test("searchable items include rich Spotlight metadata and hydrated model context")
    func searchableItemIncludesRichMetadataAndHydrationContext() throws {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let modifiedAt = Date(timeIntervalSince1970: 1_750_000_300)
        let document = SearchIndexedDocument(
            id: "music-nft-1",
            domain: .nft,
            title: "Aurora Drift",
            subtitle: "Waves",
            contentDescription: "NFT: Aurora Drift. Collection: Waves.",
            keywords: ["nft", "music"],
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            destination: .musicItem(id: "music-nft-1"),
            metadata: SearchSpotlightDocumentMetadata.empty.replacing(
                domainLabel: "AuraPlay media NFT",
                chainName: Chain.ethMainnet.routingDisplayName,
                accountAddress: "0x1111111111111111111111111111111111111111",
                contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                tokenID: "42",
                tokenStandard: "ERC721",
                collectionName: "Waves",
                artistName: "Nova",
                mediaKind: "audio",
                isPlayable: true,
                hydrationContext: "Playback URL is locally available."
            )
        )

        let indexedItem = document.searchableItem
        let hydratedItem = document.hydratedSearchableItem
        let indexedKeywords = indexedItem.attributeSet.keywords ?? []
        let indexedText = indexedItem.attributeSet.textContent ?? ""
        let hydratedText = hydratedItem.attributeSet.textContent ?? ""

        #expect(indexedItem.attributeSet.contentCreationDate == createdAt)
        #expect(indexedItem.attributeSet.contentModificationDate == modifiedAt)
        #expect(indexedItem.attributeSet.containerDisplayName == "Waves")
        #expect(indexedItem.attributeSet.containerIdentifier == "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(indexedKeywords.contains("playable"))
        #expect(indexedKeywords.contains("auralis:documentdomain=nft"))
        #expect(indexedKeywords.contains("auralis:mediakind=audio"))
        #expect(indexedKeywords.contains("auralis:isplayable=true"))
        #expect(!indexedText.contains("Artist: Nova"))
        #expect(hydratedText.contains("Artist: Nova"))
        #expect(hydratedText.contains("Playback URL is locally available."))
    }

    @Test("assistant request chooses focused tool plans from query kind and words")
    func assistantRequestChoosesFocusedToolPlans() {
        let scope = SearchScope(accountAddress: "0x1111111111111111111111111111111111111111", chain: .ethMainnet)

        let tokenRequest = SearchAssistantRequest(query: "USDC", scope: scope, kind: .tokenSymbol)
        #expect(tokenRequest.toolPlan.usesSimilarityMatch)
        #expect(!tokenRequest.toolPlan.usesDateMatch)
        #expect(!tokenRequest.toolPlan.usesMediaCapabilityStage)
        #expect(!tokenRequest.toolPlan.usesReceiptRollupStage)

        let mediaRequest = SearchAssistantRequest(query: "show playable music NFTs", scope: scope, kind: .text)
        #expect(mediaRequest.toolPlan.usesSimilarityMatch)
        #expect(!mediaRequest.toolPlan.usesDateMatch)
        #expect(mediaRequest.toolPlan.usesMediaCapabilityStage)
        #expect(!mediaRequest.toolPlan.usesReceiptRollupStage)

        let receiptRequest = SearchAssistantRequest(query: "which receipts failed recently", scope: scope, kind: .text)
        #expect(receiptRequest.toolPlan.usesSimilarityMatch)
        #expect(receiptRequest.toolPlan.usesDateMatch)
        #expect(!receiptRequest.toolPlan.usesMediaCapabilityStage)
        #expect(receiptRequest.toolPlan.usesReceiptRollupStage)
    }

    @Test("existing AuraPlay Spotlight items map by domain identifier")
    func auraPlayRawSearchableItemMapsToMusicDestination() throws {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .audio)
        attributeSet.title = "Late Night Synth"
        attributeSet.contentDescription = "Artist: Aura"
        let item = CSSearchableItem(
            uniqueIdentifier: "media-1",
            domainIdentifier: SearchIndexedDocument.Domain.auraPlayMedia.rawValue,
            attributeSet: attributeSet
        )

        let match = try #require(SearchLocalMatch(searchableItem: item))
        #expect(match.kind == .musicItem)
        #expect(match.destination == .musicItem(id: "media-1"))
    }

    #if canImport(FoundationModels)
    @available(iOS 27.0, *)
    @Test("media capability stage scores playable media results")
    func mediaCapabilityStageScoresPlayableMediaResults() async throws {
        let playableAttributes = CSSearchableItemAttributeSet(contentType: .audio)
        playableAttributes.title = "Aurora Drift"
        playableAttributes.contentDescription = "Type: AuraPlay media NFT. Artist: Nova."
        playableAttributes.keywords = [
            "music",
            "auralis:documentdomain=nft",
            "auralis:mediakind=audio",
            "auralis:isplayable=true",
        ]
        let playable = CSSearchableItem(
            uniqueIdentifier: "auralis.search.nft:music-nft-1",
            domainIdentifier: SearchIndexedDocument.Domain.nft.rawValue,
            attributeSet: playableAttributes
        )

        let visualAttributes = CSSearchableItemAttributeSet(contentType: .image)
        visualAttributes.title = "Still Image"
        visualAttributes.contentDescription = "Type: NFT."
        visualAttributes.keywords = [
            "auralis:documentdomain=nft",
            "auralis:mediakind=visual",
            "auralis:isplayable=false",
        ]
        let visual = CSSearchableItem(
            uniqueIdentifier: "auralis.search.nft:visual-nft-1",
            domainIdentifier: SearchIndexedDocument.Domain.nft.rawValue,
            attributeSet: visualAttributes
        )

        let stage = AuralisMediaCapabilityStage(preferredMediaKind: "audio", threshold: 0.2)
        let output = try await stage.execute(items: [visual, playable])

        guard case .scoredItems(let scoredItems) = output.payload else {
            Issue.record("Expected scored media results")
            return
        }

        #expect(scoredItems.first?.item.uniqueIdentifier == "auralis.search.nft:music-nft-1")
        #expect(scoredItems.count == 1)
        #expect((scoredItems.first?.score ?? 0) >= 0.2)
    }

    @available(iOS 27.0, *)
    @Test("receipt rollup stage groups receipt results by status")
    func receiptRollupStageGroupsReceiptResultsByStatus() async throws {
        let success = receiptSearchableItem(id: "success", status: "Succeeded")
        let failed = receiptSearchableItem(id: "failed", status: "Failed")
        let anotherFailed = receiptSearchableItem(id: "failed-2", status: "Failed")

        let stage = AuralisReceiptRollupStage(groupBy: "status")
        let output = try await stage.execute(items: [success, failed, anotherFailed])

        guard case .table(let table) = output.payload else {
            Issue.record("Expected receipt rollup table")
            return
        }

        let firstCellDescription = table.rows.isEmpty || table.rows[0].values.isEmpty
            ? ""
            : String(describing: table.rows[0].values[0])

        #expect(table.rows.count == 2)
        #expect(firstCellDescription.contains("Failed"))
    }

    @available(iOS 27.0, *)
    private func receiptSearchableItem(id: String, status: String) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = "Receipt \(id)"
        attributes.contentDescription = "Receipt event."
        attributes.keywords = [
            "receipt",
            "auralis:documentdomain=receipt",
            "auralis:receiptstatus=\(status)",
            "auralis:receipttrigger=Search",
            "auralis:receiptscope=wallet",
            "auralis:chain=Ethereum",
        ]
        return CSSearchableItem(
            uniqueIdentifier: "auralis.search.receipt:\(id)",
            domainIdentifier: SearchIndexedDocument.Domain.receipt.rawValue,
            attributeSet: attributes
        )
    }
    #endif
    #endif
}
