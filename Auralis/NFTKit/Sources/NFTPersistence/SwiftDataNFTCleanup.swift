import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import SwiftData

extension ModelContext {
    public func deleteNFTsScopedToAccount(_ accountAddress: String) throws {
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == accountAddress
            }
        )

        for nft in try fetch(descriptor) {
            delete(nft)
        }

        try pruneOrphanedNFTSharedModels()
    }

    public func deleteAllNFTData() throws {
        for nft in try fetch(FetchDescriptor<NFT>()) {
            delete(nft)
        }
        try pruneOrphanedNFTSharedModels()
    }

    public func pruneOrphanedNFTSharedModels() throws {
        let allNFTs = try fetch(FetchDescriptor<NFT>())
        let referencedContractIDs = Set(allNFTs.map(\.contract.id))
        let referencedCollectionIDs = Set(allNFTs.compactMap(\.collection?.id))

        // Contracts and collections are shared across many NFTs, so they are
        // intentionally pruned separately from NFT-owned child models.
        let persistedContracts = try fetch(FetchDescriptor<NFT.Contract>())
        for contract in persistedContracts where !referencedContractIDs.contains(contract.id) {
            delete(contract)
        }

        let persistedCollections = try fetch(FetchDescriptor<NFT.Collection>())
        for collection in persistedCollections where !referencedCollectionIDs.contains(collection.id) {
            delete(collection)
        }
    }
}
