@testable import Auralis
import AccountStorage
import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import SwiftData
import Testing
import TokenStorage

@MainActor
@Suite
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

        context.insert(makeFixtureNFT(tokenId: "undo-1", accountAddress: removed.address))
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
        let nft = makeFixtureNFT(tokenId: "rollback-1")
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

private func makeFixtureNFT(
    tokenId: String,
    accountAddress: String = "0x1111111111111111111111111111111111111111",
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e"
) -> NFT {
    let network: Chain = .ethMainnet
    let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"

    return NFT(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFT.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        name: "Fixture \(tokenId)",
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
        contentType: "audio/mpeg",
        collectionName: "Fixture Collection",
        artistName: "Fixture Artist",
        animationUrl: "https://example.com/\(tokenId).mp3",
        audioUrl: "https://example.com/\(tokenId).mp3"
    )
}
