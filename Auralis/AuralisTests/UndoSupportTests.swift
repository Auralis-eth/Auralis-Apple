@testable import AuralisCrypto
@testable import Auralis
import AuralisTestSupport
import Foundation
import AuralisOperators
import SwiftData
import Testing

@MainActor
struct UndoSupportTests {
    private enum InjectedParticipantFailure: Error {
        case afterMusicDeletion
    }

    @Test("playlist deletion registers an undoable transaction on the primary store schema")
    func playlistDeletionCanUndo() throws {
        let container = try TestModelContainers.primaryStore(undoEnabled: true)
        let context = container.mainContext
        let playlist = Playlist(title: "Late Night")
        context.insert(playlist)
        try context.save()

        try PlaylistDeletionService(modelContext: context).deletePlaylist(playlist)
        #expect(try context.fetch(FetchDescriptor<Playlist>()).isEmpty)

        context.undoManager?.undo()
        context.processPendingChanges()

        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        #expect(playlists.map(\.title) == ["Late Night"])
    }

    @Test("account removal undo restores the account and its scoped support data")
    func accountRemovalCanUndo() async throws {
        let container = try TestModelContainers.primaryStore(undoEnabled: true)
        let context = container.mainContext
        let store = SwiftDataAccountStore(
            modelContext: context,
            scopedPersistenceParticipants: makeAppAccountScopedPersistenceParticipants()
        )

        let removed = try await store.createWatchAccount(
            from: "0x1010101010101010101010101010101010101010",
            now: Date(timeIntervalSince1970: 100)
        )
        _ = try await store.createWatchAccount(
            from: "0x2020202020202020202020202020202020202020",
            now: Date(timeIntervalSince1970: 200)
        )

        let nft = NFTFixture.music.with {
            $0.tokenId = "undo-1"
            $0.accountAddress = removed.address
        }.build()
        nft.attributes = [NFT.Attribute(value: "Blue", traitType: "Color")]
        nft.externalUrl = "https://example.com/nft"
        nft.backgroundColor = "112233"
        nft.tokenHash = "0xundo"
        nft.aspectRatio = 1.5
        nft.image = NFT.Image(originalUrl: "ipfs://art", thumbnailUrl: "https://example.com/thumb.png")
        nft.image?.secureUrl = "https://example.com/secure.png"
        nft.raw = NFT.Raw(tokenUri: "ipfs://metadata", metadata: ["genre": .string("ambient")])
        nft.raw?.error = "historical warning"
        let tag = try Tag(name: "Undo Tag")
        nft.tags = [tag]
        let playlist = Playlist(name: "Undo Playlist", tracks: [nft])
        context.insert(tag)
        context.insert(playlist)
        context.insert(nft)
        context.insert(
            TokenHolding(
                accountAddress: removed.address,
                chain: .ethMainnet,
                symbol: "ETH",
                displayName: "Ether",
                amountDisplay: "1.0",
                balanceKind: .native
            )
        )
        context.insert(
            SearchHistoryRecord(
                accountAddressRawValue: removed.address,
                normalizedQuery: "undo",
                query: "Undo"
            )
        )
        context.insert(
            MusicLibraryItem(
                id: "undo-music",
                sourceNFTID: nft.id,
                accountAddressRawValue: removed.address,
                networkRawValue: Chain.ethMainnet.rawValue,
                title: "Undo Track",
                artistName: "Auralis",
                collectionName: "Recovery",
                normalizedTitleKey: "undo track",
                normalizedArtistKey: "auralis",
                normalizedCollectionKey: "recovery",
                artworkURLString: "https://example.com/art.png",
                contentType: "audio/mpeg",
                playbackURLString: "https://example.com/track.mp3",
                availability: .ready,
                availabilityReason: nil,
                sourceUpdatedAtRawValue: "2026-10-23T00:00:00Z",
                indexedAt: Date(timeIntervalSince1970: 300)
            )
        )
        try context.save()

        _ = try await store.removeAccount(
            address: removed.address,
            activeAddress: removed.address
        )

        #expect(try context.fetch(FetchDescriptor<EOAccount>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT>()).contains(where: { $0.accountAddressRawValue == removed.address }) == false)
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).contains(where: { $0.accountAddressRawValue == removed.address }) == false)
        #expect(SearchHistoryStore(modelContext: context).entries(for: removed.address).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MusicLibraryItem>()).isEmpty)

        context.undoManager?.undo()
        context.processPendingChanges()

        #expect(try context.fetch(FetchDescriptor<EOAccount>()).contains(where: { $0.address == removed.address }))
        let restoredNFT = try #require(
            context.fetch(FetchDescriptor<NFT>()).first(where: { $0.accountAddressRawValue == removed.address })
        )
        #expect(restoredNFT.attributes?.map(\.value) == ["Blue"])
        #expect(restoredNFT.externalUrl == "https://example.com/nft")
        #expect(restoredNFT.backgroundColor == "112233")
        #expect(restoredNFT.tokenHash == "0xundo")
        #expect(restoredNFT.aspectRatio == 1.5)
        #expect(restoredNFT.image?.originalUrl == "ipfs://art")
        #expect(restoredNFT.image?.secureUrl == "https://example.com/secure.png")
        #expect(restoredNFT.raw?.metadata?["genre"] == .string("ambient"))
        #expect(restoredNFT.raw?.error == "historical warning")
        #expect(restoredNFT.tags?.map(\.name) == ["Undo Tag"])
        #expect(restoredNFT.playlists.map(\.title) == ["Undo Playlist"])
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).contains(where: { $0.accountAddressRawValue == removed.address }))
        #expect(SearchHistoryStore(modelContext: context).entries(for: removed.address).map(\.query) == ["Undo"])
        let restoredMusicItem = try #require(context.fetch(FetchDescriptor<MusicLibraryItem>()).first)
        #expect(restoredMusicItem.id == "undo-music")
        #expect(restoredMusicItem.title == "Undo Track")
        #expect(restoredMusicItem.availability == .ready)
        #expect(restoredMusicItem.indexedAt == Date(timeIntervalSince1970: 300))
    }

    @Test("account participant failure rolls back all earlier domain deletions")
    func accountParticipantFailureRollsBackAllDomains() async throws {
        let container = try TestModelContainers.primaryStore()
        let context = container.mainContext
        let store = SwiftDataAccountStore(
            modelContext: context,
            eventRecorder: NoOpAccountEventRecorder(),
            scopedPersistenceParticipants: makeAppAccountScopedPersistenceParticipants(),
            participantDidDelete: { participant in
                if participant == "music" {
                    throw InjectedParticipantFailure.afterMusicDeletion
                }
            }
        )
        let account = try await store.createWatchAccount(
            from: "0x3030303030303030303030303030303030303030"
        )
        let nft = NFTFixture.music.with {
            $0.tokenId = "rollback-participant"
            $0.accountAddress = account.address
        }.build()
        context.insert(nft)
        context.insert(
            TokenHolding(
                accountAddress: account.address,
                chain: .ethMainnet,
                symbol: "ETH",
                displayName: "Ether",
                amountDisplay: "1.0",
                balanceKind: .native
            )
        )
        context.insert(
            SearchHistoryRecord(
                accountAddressRawValue: account.address,
                normalizedQuery: "rollback",
                query: "Rollback"
            )
        )
        context.insert(
            MusicLibraryItem(
                id: "rollback-participant-music",
                sourceNFTID: nft.id,
                accountAddressRawValue: account.address,
                networkRawValue: Chain.ethMainnet.rawValue,
                title: "Rollback Track",
                artistName: nil,
                collectionName: nil,
                normalizedTitleKey: "rollback track",
                normalizedArtistKey: "",
                normalizedCollectionKey: "",
                artworkURLString: nil,
                contentType: "audio/mpeg",
                playbackURLString: nil,
                availability: .unavailable,
                availabilityReason: "fixture",
                sourceUpdatedAtRawValue: nil
            )
        )
        try context.save()

        await #expect(throws: InjectedParticipantFailure.afterMusicDeletion) {
            _ = try await store.removeAccount(address: account.address, activeAddress: account.address)
        }

        #expect(try context.fetch(FetchDescriptor<EOAccount>()).map(\.address) == [account.address])
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MusicLibraryItem>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SearchHistoryRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT>()).count == 1)
    }

    @Test("rollback-safe delete helpers restore state after a failure")
    func rollbackSafeDeleteRestoresStateAfterFailure() throws {
        enum Failure: Error {
            case forced
        }

        let container = try TestModelContainers.primaryStore()
        let context = container.mainContext
        let nft = NFTFixture.music.with { $0.tokenId = "rollback-1" }.build()
        context.insert(nft)
        try context.save()

        do {
            try context.performRollbackSafeMutation {
                try context.deleteAllNFTData()
                throw Failure.forced
            }
        } catch Failure.forced {
        }

        #expect(try context.fetch(FetchDescriptor<NFT>()).map(\.id) == [nft.id])
        #expect(try context.fetch(FetchDescriptor<NFT.Contract>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT.Collection>()).count == 1)
    }
}
