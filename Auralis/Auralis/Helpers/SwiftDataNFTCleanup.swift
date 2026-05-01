import Foundation
import SwiftData

extension ModelContext {
    func deleteAccountScopedSupportData(accountAddress: String) throws {
        try delete(
            model: TokenHolding.self,
            where: #Predicate<TokenHolding> { holding in
                holding.accountAddressRawValue == accountAddress
            }
        )
        try delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            }
        )
    }

    func deleteNFTsScopedToAccount(_ accountAddress: String) throws {
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

    func deleteAllNFTData() throws {
        try delete(
            model: NFT.self,
            where: #Predicate<NFT> { _ in true }
        )
        try pruneOrphanedNFTSharedModels()
    }

    func pruneOrphanedNFTSharedModels() throws {
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
