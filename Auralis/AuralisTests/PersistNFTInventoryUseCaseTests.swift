@testable import Auralis
import Foundation
import SwiftData
import Testing

@Suite
struct PersistNFTInventoryUseCaseTests {
    @Test("upserts new NFTs and synchronizes tracked counts")
    @MainActor
    func upsertsInventoryAndSyncsCount() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        context.insert(account)
        try context.save()

        let inventory = PreparedNFTInventory(
            nfts: [
                makeRefreshFixtureNFT(tokenId: "1", accountAddress: account.address),
                makeRefreshFixtureNFT(tokenId: "2", accountAddress: account.address)
            ]
        )
        let useCase = LivePersistNFTInventoryUseCase()

        try await useCase.persist(
            inventory,
            accountAddress: account.address,
            chain: .ethMainnet,
            modelContext: context
        )

        let persistedNFTs = try context.fetch(FetchDescriptor<NFT>())
        let persistedAccount = try #require(
            context.fetch(
                FetchDescriptor<EOAccount>(
                    predicate: #Predicate<EOAccount> { $0.address == account.address }
                )
            ).first
        )

        #expect(persistedNFTs.count == 2)
        #expect(persistedAccount.trackedNFTCount == 2)
    }

    @Test("merges existing NFTs without clobbering local tags")
    @MainActor
    func mergePreservesLocalTags() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let tag = try Tag(name: "Local Favorite")
        let existing = makeRefreshFixtureNFT(tokenId: "7")
        existing.tags = [tag]
        context.insert(tag)
        context.insert(existing)
        try context.save()

        let refreshed = makeRefreshFixtureNFT(tokenId: "7")
        refreshed.name = "Refreshed Name"
        let inventory = PreparedNFTInventory(nfts: [refreshed])
        let useCase = LivePersistNFTInventoryUseCase()

        try await useCase.persist(
            inventory,
            accountAddress: "0x1234567890abcdef1234567890abcdef12345678",
            chain: .ethMainnet,
            modelContext: context
        )

        let persisted = try #require(
            context.fetch(
                FetchDescriptor<NFT>(
                    predicate: #Predicate<NFT> { $0.tokenId == "7" }
                )
            ).first
        )

        #expect(persisted.name == "Refreshed Name")
        #expect(persisted.tags?.map(\.name) == ["Local Favorite"])
    }

    @Test("cleanup removes stale NFTs in scope and prunes orphaned shared models")
    @MainActor
    func cleanupRemovesStaleInventoryAndPrunesOrphans() async throws {
        let container = try makeNFTRefreshContainer()
        let context = ModelContext(container)
        let account = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")
        let stale = makeRefreshFixtureNFT(
            contractAddress: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tokenId: "stale",
            accountAddress: account.address
        )
        context.insert(account)
        context.insert(stale)
        try context.save()

        let fresh = makeRefreshFixtureNFT(
            contractAddress: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            tokenId: "fresh",
            accountAddress: account.address
        )
        let inventory = PreparedNFTInventory(nfts: [fresh])
        let useCase = LivePersistNFTInventoryUseCase()

        try await useCase.persist(
            inventory,
            accountAddress: account.address,
            chain: .ethMainnet,
            modelContext: context
        )
        try await useCase.cleanupStaleInventory(
            currentNFTIDs: inventory.nfts.map(\.id),
            accountAddress: account.address,
            chain: .ethMainnet,
            modelContext: context
        )

        let persistedNFTs = try context.fetch(FetchDescriptor<NFT>())
        let contracts = try context.fetch(FetchDescriptor<NFT.Contract>())
        let collections = try context.fetch(FetchDescriptor<NFT.Collection>())

        #expect(persistedNFTs.count == 1)
        #expect(persistedNFTs.first?.tokenId == "fresh")
        #expect(contracts.count == 1)
        #expect(contracts.first?.address == "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(collections.count == 1)
        #expect(collections.first?.contractAddress == "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
    }
}
