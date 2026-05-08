import AuralisPrimaryModels
import Foundation
import SwiftData

extension ModelContext {
    public func deleteAccountScopedSupportData(accountAddress: String) throws {
        try delete(
            model: StoredReceipt.self,
            where: #Predicate<StoredReceipt> { receipt in
                receipt.accountAddress == accountAddress
            }
        )
        try delete(
            model: TokenHolding.self,
            where: #Predicate<TokenHolding> { holding in
                holding.accountAddressRawValue == accountAddress
            }
        )
        try delete(
            model: MusicLibraryItem.self,
            where: #Predicate<MusicLibraryItem> { item in
                item.accountAddressRawValue == accountAddress
            }
        )
        try delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            }
        )

        let accountDescriptor = FetchDescriptor<EOAccount>(
            predicate: #Predicate<EOAccount> { account in
                account.address == accountAddress
            }
        )
        if let account = try fetch(accountDescriptor).first {
            account.clearAllAuraPlaySyncState()
        }
    }

    public func deleteAllShellSupportData() throws {
        for receipt in try fetch(FetchDescriptor<StoredReceipt>()) {
            delete(receipt)
        }
        try delete(
            model: TokenHolding.self,
            where: #Predicate<TokenHolding> { _ in true }
        )
        for item in try fetch(FetchDescriptor<MusicLibraryItem>()) {
            delete(item)
        }
        try delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { _ in true }
        )
        try delete(
            model: Playlist.self,
            where: #Predicate<Playlist> { _ in true }
        )

        for account in try fetch(FetchDescriptor<EOAccount>()) {
            account.clearAllAuraPlaySyncState()
        }
    }

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
