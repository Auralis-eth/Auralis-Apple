@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import ReceiptStorage
import SwiftData
import Testing

struct AuraPlayPlaybackReceiptEffectTests {
    @Test("runtime persists start, queue, and one completion receipt per playback")
    @MainActor
    func runtimePersistsReceiptEffectsWithoutDuplicateCompletion() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(modelContext: context)
        let runtime = try AuraPlayPlaybackRuntime(
            defaults: try #require(UserDefaults(suiteName: #function))
        )
        runtime.configureMusicReceiptLogger(MusicReceiptEventLogger(receiptStore: receiptStore))
        let nft = makePlaybackReceiptNFT()

        await runtime.testRecordPlaybackStarted(for: nft, triggerCause: .userInitiated)
        await runtime.testRecordQueueChanged(
            operation: "next",
            affectedMediaIDs: [nft.id],
            beforeSummary: MusicReceiptStateSummary(values: ["upcomingCount": .number(1)]),
            afterSummary: MusicReceiptStateSummary(values: ["upcomingCount": .number(0)]),
            triggerCause: .userInitiated,
            nft: nft
        )
        await runtime.testRecordPlaybackCompleted(
            mediaID: nft.id,
            title: nft.name,
            artist: nft.artistName,
            triggerCause: .autoAdvance
        )
        await runtime.testRecordPlaybackCompleted(
            mediaID: nft.id,
            title: nft.name,
            artist: nft.artistName,
            triggerCause: .autoAdvance
        )

        let receipts = try await receiptStore.latest(limit: 10)
        #expect(receipts.map(\.trigger).sorted() == [
            "music.playback.completed",
            "music.playback.started",
            "music.queue.changed"
        ])
        #expect(receipts.filter { $0.trigger == "music.playback.completed" }.count == 1)

        let queueReceipt = try #require(receipts.first { $0.trigger == "music.queue.changed" })
        #expect(queueReceipt.details.values["operation"] == .string("next"))
        #expect(queueReceipt.details.values["affectedMediaIDs"] == .array([.string(nft.id)]))

        let startedReceipt = try #require(receipts.first { $0.trigger == "music.playback.started" })
        #expect(startedReceipt.details.values["affectedMediaIDs"] == .array([.string(nft.id)]))
        #expect(startedReceipt.details.values["trigger"] == .string("user_initiated"))
    }

    private func makePlaybackReceiptNFT() -> NFT {
        let accountAddress = "0x1111111111111111111111111111111111111111"
        let contractAddress = "0x2222222222222222222222222222222222222222"
        return NFT(
            id: "\(accountAddress):eth-mainnet:\(contractAddress):1",
            contract: NFT.Contract(address: contractAddress, chain: .ethMainnet),
            tokenId: "1",
            name: "Receipt Track",
            image: nil,
            raw: nil,
            collection: NFT.Collection(
                name: "Receipt Collection",
                chain: .ethMainnet,
                contractAddress: contractAddress
            ),
            tokenUri: "ipfs://receipt-track",
            timeLastUpdated: "2026-01-01T00:00:00Z",
            network: .ethMainnet,
            accountAddress: accountAddress,
            contentType: "audio/mpeg",
            collectionName: "Receipt Collection",
            artistName: "Auralis",
            animationUrl: "https://example.com/receipt-track.mp3",
            audioUrl: "https://example.com/receipt-track.mp3"
        )
    }
}
