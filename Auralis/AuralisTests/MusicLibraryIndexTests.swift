import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct MusicLibraryIndexTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([NFT.self, Tag.self, StoredReceipt.self, MusicLibraryItem.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("music library index rebuild loads from scoped local NFTs and ignores non-music records")
    @MainActor
    func rebuildLoadsScopedMusicNFTs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        context.insert(
            makeMusicFixtureNFT(
                tokenId: "music-1",
                title: "Aurora Bloom",
                artistName: "Luna Cipher",
                audioURL: "https://example.com/audio/aurora-bloom.mp3"
            )
        )
        context.insert(
            makeMusicFixtureNFT(
                tokenId: "music-2",
                title: "Base Tide",
                artistName: "Chain Echo",
                network: .baseMainnet,
                audioURL: "https://example.com/audio/base-tide.mp3"
            )
        )
        context.insert(
            makeVisualFixtureNFT(
                contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                tokenId: "visual-1",
                title: "Still Image"
            )
        )
        try context.save()

        let indexer = SwiftDataMusicLibraryIndexer(modelContext: context)

        let result = try indexer.rebuildIndex(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "music-rebuild-load",
            receiptEventLogger: nil
        )

        let items = try context.fetch(FetchDescriptor<MusicLibraryItem>())

        #expect(result == MusicLibraryIndexRebuildResult(scannedCount: 1, writtenCount: 1, removedCount: 0))
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.title == "Aurora Bloom")
        #expect(item.artistName == "Luna Cipher")
        #expect(item.networkRawValue == Chain.ethMainnet.rawValue)
        #expect(item.availability == .ready)
        #expect(item.playbackURLString == "https://example.com/audio/aurora-bloom.mp3")
    }

    @Test("music library index rebuild removes stale rows when source NFTs disappear from the active scope")
    @MainActor
    func rebuildRemovesStaleRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"

        context.insert(
            makeMusicFixtureNFT(
                tokenId: "music-1",
                title: "First Pass",
                accountAddress: accountAddress,
                audioURL: "https://example.com/audio/first-pass.mp3"
            )
        )
        try context.save()

        let indexer = SwiftDataMusicLibraryIndexer(modelContext: context)
        _ = try indexer.rebuildIndex(
            accountAddress: accountAddress,
            chain: .ethMainnet,
            correlationID: "music-rebuild-prime",
            receiptEventLogger: nil
        )

        for nft in try context.fetch(FetchDescriptor<NFT>()) {
            context.delete(nft)
        }
        try context.save()

        let result = try indexer.rebuildIndex(
            accountAddress: accountAddress,
            chain: .ethMainnet,
            correlationID: "music-rebuild-cleanup",
            receiptEventLogger: nil
        )

        let items = try context.fetch(FetchDescriptor<MusicLibraryItem>())

        #expect(result == MusicLibraryIndexRebuildResult(scannedCount: 0, writtenCount: 0, removedCount: 1))
        #expect(items.isEmpty)
    }

    @Test("music library index rebuild emits started and completed receipts with one shared correlation ID")
    @MainActor
    func rebuildEmitsReceipts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let receiptLogger = ReceiptEventLogger(receiptStore: receiptStore)

        context.insert(
            makeMusicFixtureNFT(
                tokenId: "music-1",
                title: "Receipt Track",
                audioURL: "https://example.com/audio/receipt-track.mp3"
            )
        )
        try context.save()

        let indexer = SwiftDataMusicLibraryIndexer(modelContext: context)
        let correlationID = "music-library-correlation"

        _ = try indexer.rebuildIndex(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: correlationID,
            receiptEventLogger: receiptLogger
        )

        let receipts = try receiptStore.receipts(forCorrelationID: correlationID, limit: 10)

        #expect(receipts.map { $0.kind } == [
            "music.library_index.completed",
            "music.library_index.started"
        ])
        #expect(receipts.allSatisfy { $0.correlationID == correlationID })
        let completed = try #require(receipts.first(where: { $0.kind == "music.library_index.completed" }))
        #expect(completed.details.values["scannedCount"] == ReceiptJSONValue.number(1))
        #expect(completed.details.values["writtenCount"] == ReceiptJSONValue.number(1))
        #expect(completed.details.values["removedCount"] == ReceiptJSONValue.number(0))
    }

    @Test("saved music library rows remain readable from a fresh model context after rebuild")
    @MainActor
    func rebuiltRowsRemainReadableFromFreshContext() throws {
        let container = try makeContainer()
        let writeContext = ModelContext(container)

        writeContext.insert(
            makeMusicFixtureNFT(
                tokenId: "music-1",
                title: "Persisted Echo",
                artistName: "Archive Unit",
                audioURL: "https://example.com/audio/persisted-echo.mp3"
            )
        )
        try writeContext.save()

        let indexer = SwiftDataMusicLibraryIndexer(modelContext: writeContext)
        _ = try indexer.rebuildIndex(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            correlationID: "music-rebuild-persisted",
            receiptEventLogger: nil
        )

        let readContext = ModelContext(container)
        let items = try readContext.fetch(FetchDescriptor<MusicLibraryItem>())

        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.title == "Persisted Echo")
        #expect(item.artistName == "Archive Unit")
        #expect(item.sourceNFTID.contains("music-1"))
    }
}

private func makeMusicFixtureNFT(
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e",
    tokenId: String,
    title: String,
    artistName: String? = "Luna Cipher",
    network: Chain = .ethMainnet,
    accountAddress: String = "0x1234567890abcdef1234567890abcdef12345678",
    audioURL: String,
    contentType: String = "audio/mpeg"
) -> NFT {
    let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"

    return NFT(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFT.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        name: title,
        image: nil,
        raw: nil,
        collection: NFT.Collection(
            name: "Fixture Collection",
            chain: network,
            contractAddress: contractAddress
        ),
        tokenUri: "ipfs://fixture-\(tokenId)",
        timeLastUpdated: "2025-01-01T00:00:00Z",
        network: network,
        accountAddress: accountAddress,
        contentType: contentType,
        collectionName: "Fixture Collection",
        artistName: artistName,
        animationUrl: audioURL,
        audioUrl: audioURL
    )
}

private func makeVisualFixtureNFT(
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e",
    tokenId: String,
    title: String,
    network: Chain = .ethMainnet,
    accountAddress: String = "0x1234567890abcdef1234567890abcdef12345678"
) -> NFT {
    let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"

    return NFT(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFT.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        name: title,
        image: nil,
        raw: nil,
        collection: NFT.Collection(
            name: "Fixture Collection",
            chain: network,
            contractAddress: contractAddress
        ),
        tokenUri: "ipfs://fixture-\(tokenId)",
        timeLastUpdated: "2025-01-01T00:00:00Z",
        network: network,
        accountAddress: accountAddress,
        contentType: "image/png",
        collectionName: "Fixture Collection",
        artistName: "Visual Unit",
        animationUrl: nil,
        audioUrl: nil
    )
}
