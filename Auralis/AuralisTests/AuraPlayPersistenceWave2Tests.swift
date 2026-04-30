@testable import Auralis
import Foundation
import SwiftData
import Testing

@MainActor
@Suite
struct AuraPlayPersistenceWave2Tests {
    @Test("Wave 2 schema registers wallet token and media models")
    func schemaContainsWave2CoreEntities() {
        let modelNames = Set(AuraPlaySchemaV1.models.map { String(describing: $0) })

        #expect(modelNames.contains("AuraPlayWallet"))
        #expect(modelNames.contains("AuraPlayNFTToken"))
        #expect(modelNames.contains("AuraPlayMediaItem"))
    }

    @Test("wallet service can upsert a scoped wallet into the AuraPlay container")
    func walletServiceUpsertsScopedWallet() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let walletService = AuraPlayWalletService(modelContainer: container)

        let walletID = try await walletService.upsert(
            AuraPlayWalletUpsertRequest(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                displayName: "Aura Wallet",
                syncedAt: .now
            )
        )

        let context = ModelContext(container)
        let wallets = try context.fetch(FetchDescriptor<AuraPlayWallet>())

        #expect(walletID == "0x1234567890abcdef1234567890abcdef12345678:eth-mainnet")
        #expect(wallets.count == 1)
        #expect(wallets.first?.displayName == "Aura Wallet")
    }

    @Test("library repository prefers persisted AuraPlay media once a scoped wallet exists")
    func libraryRepositoryPrefersPersistedMediaGraph() async throws {
        let container = try AppModelContainer.make(inMemory: true)
        let walletService = AuraPlayWalletService(modelContainer: container)
        let tokenService = AuraPlayNFTTokenService(modelContainer: container)
        let mediaItemService = AuraPlayMediaItemService(modelContainer: container)
        let scope = AuraPlayLibraryScope(
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet
        )

        let walletID = try await walletService.upsert(
            AuraPlayWalletUpsertRequest(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                displayName: "Aura Wallet",
                syncedAt: .now
            )
        )
        let tokenCompositeID = AuraPlayNFTToken.makeCompositeID(
            walletID: walletID,
            contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            tokenID: "1"
        )

        try await tokenService.replaceAll(
            walletID: walletID,
            requests: [
                AuraPlayNFTTokenUpsertRequest(
                    walletID: walletID,
                    sourceNFTID: "nft-1",
                    contractAddressRawValue: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                    tokenID: "1",
                    tokenType: "ERC721",
                    title: "Genesis Track",
                    artistName: "Aura",
                    collectionName: "Origin",
                    artworkURLString: "https://example.com/artwork.png",
                    playbackURLString: "https://example.com/track.mp3",
                    contentType: "audio/mpeg",
                    sourceUpdatedAtRawValue: "2025-01-01T00:00:00Z"
                )
            ],
            syncedAt: .now
        )
        try await mediaItemService.replaceAll(
            walletID: walletID,
            requests: [
                AuraPlayMediaItemUpsertRequest(
                    walletID: walletID,
                    tokenCompositeID: tokenCompositeID,
                    sourceNFTID: "nft-1",
                    accountAddressRawValue: "0x1234567890abcdef1234567890abcdef12345678",
                    chain: .ethMainnet,
                    title: "Genesis Track",
                    artistName: "Aura",
                    collectionName: "Origin",
                    normalizedTitleKey: "genesis track",
                    normalizedArtistKey: "aura",
                    normalizedCollectionKey: "origin",
                    artworkURLString: "https://example.com/artwork.png",
                    playbackURLString: "https://example.com/track.mp3",
                    contentType: "audio/mpeg",
                    sourceUpdatedAtRawValue: "2025-01-01T00:00:00Z",
                    hasArtwork: true,
                    hasAudio: true,
                    isPlayable: true,
                    isSearchable: true
                )
            ],
            syncedAt: .now
        )

        let repository = LiveAuraPlayLibraryRepository(
            indexer: MockMusicLibraryIndexer(),
            receiptEventLogger: ReceiptEventLogger(receiptStore: UnusedReceiptStore()),
            modelContainer: container
        )

        #expect(try repository.itemCount(in: scope) == 1)
        #expect(try repository.needsRebuild(in: scope) == false)
    }
}

@MainActor
private final class MockMusicLibraryIndexer: MusicLibraryIndexing {
    func itemCount(accountAddress: String?, chain: Chain) throws -> Int {
        99
    }

    func needsRebuild(accountAddress: String?, chain: Chain) throws -> Bool {
        true
    }

    func rebuildIndex(
        accountAddress: String?,
        chain: Chain,
        correlationID: String?,
        receiptEventLogger: ReceiptEventLogger?
    ) async throws -> MusicLibraryIndexRebuildResult {
        MusicLibraryIndexRebuildResult(scannedCount: 0, writtenCount: 0, removedCount: 0)
    }
}

@MainActor
private final class UnusedReceiptStore: ReceiptStore {
    func append(_ receipt: ReceiptDraft) async throws -> ReceiptRecord {
        fatalError("Unused in AuraPlayPersistenceWave2Tests")
    }

    func latest(limit: Int) throws -> [ReceiptRecord] {
        []
    }

    func receipts(
        forCorrelationID correlationID: String,
        limit: Int
    ) throws -> [ReceiptRecord] {
        []
    }

    func exportAll() throws -> Data {
        Data()
    }

    func resetAll() async throws {}
}
