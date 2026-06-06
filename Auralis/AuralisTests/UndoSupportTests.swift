@testable import Auralis
import AccountStorage
import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisTestSupport
import Foundation
import SwiftData
import Testing
import TokenStorage

@MainActor
struct UndoSupportTests {
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
        let store = SwiftDataAccountStore(modelContext: context)

        let removed = try await store.createWatchAccount(
            from: "0x1010101010101010101010101010101010101010",
            now: Date(timeIntervalSince1970: 100)
        )
        _ = try await store.createWatchAccount(
            from: "0x2020202020202020202020202020202020202020",
            now: Date(timeIntervalSince1970: 200)
        )

        context.insert(NFTFixture.music.with {
            $0.tokenId = "undo-1"
            $0.accountAddress = removed.address
        }.build())
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
        try context.save()

        _ = try await store.removeAccount(
            address: removed.address,
            activeAddress: removed.address
        )

        #expect(try context.fetch(FetchDescriptor<EOAccount>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT>()).contains(where: { $0.accountAddressRawValue == removed.address }) == false)
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).contains(where: { $0.accountAddressRawValue == removed.address }) == false)
        #expect(SearchHistoryStore(modelContext: context).entries(for: removed.address).isEmpty)

        context.undoManager?.undo()
        context.processPendingChanges()

        #expect(try context.fetch(FetchDescriptor<EOAccount>()).contains(where: { $0.address == removed.address }))
        #expect(try context.fetch(FetchDescriptor<NFT>()).contains(where: { $0.accountAddressRawValue == removed.address }))
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).contains(where: { $0.accountAddressRawValue == removed.address }))
        #expect(SearchHistoryStore(modelContext: context).entries(for: removed.address).map(\.query) == ["Undo"])
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
