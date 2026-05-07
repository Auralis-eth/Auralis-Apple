import AuralisPrimaryModels
import Foundation
import SwiftData

extension ModelContext {
    func deleteAccountScopedSupportData(accountAddress: String) throws {
        let scopedAuraPlayWalletIDs = try fetchScopedAuraPlayWalletIDs(accountAddress: accountAddress)

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
        try deleteAuraPlayGraph(
            accountAddress: accountAddress,
            walletIDs: scopedAuraPlayWalletIDs
        )
        try delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            }
        )
    }

    func deleteAllShellSupportData() throws {
        try delete(
            model: StoredReceipt.self,
            where: #Predicate<StoredReceipt> { _ in true }
        )
        try delete(
            model: TokenHolding.self,
            where: #Predicate<TokenHolding> { _ in true }
        )
        try delete(
            model: MusicLibraryItem.self,
            where: #Predicate<MusicLibraryItem> { _ in true }
        )
        try delete(
            model: AuraPlayMediaItem.self,
            where: #Predicate<AuraPlayMediaItem> { _ in true }
        )
        try delete(
            model: AuraPlayNFTToken.self,
            where: #Predicate<AuraPlayNFTToken> { _ in true }
        )
        try delete(
            model: AuraPlayWallet.self,
            where: #Predicate<AuraPlayWallet> { _ in true }
        )
        try delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { _ in true }
        )
        try delete(
            model: Playlist.self,
            where: #Predicate<Playlist> { _ in true }
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

    private func fetchScopedAuraPlayWalletIDs(accountAddress: String) throws -> [String] {
        let descriptor = FetchDescriptor<AuraPlayWallet>(
            predicate: #Predicate<AuraPlayWallet> { wallet in
                wallet.addressRawValue == accountAddress
            }
        )

        return try fetch(descriptor).map(\.id)
    }

    private func deleteAuraPlayGraph(
        accountAddress: String,
        walletIDs: [String]
    ) throws {
        try delete(
            model: AuraPlayMediaItem.self,
            where: #Predicate<AuraPlayMediaItem> { item in
                item.accountAddressRawValue == accountAddress
            }
        )

        guard !walletIDs.isEmpty else {
            return
        }

        for walletID in walletIDs {
            try delete(
                model: AuraPlayNFTToken.self,
                where: #Predicate<AuraPlayNFTToken> { token in
                    token.walletID == walletID
                }
            )
        }

        let walletDescriptor = FetchDescriptor<AuraPlayWallet>(
            predicate: #Predicate<AuraPlayWallet> { wallet in
                wallet.addressRawValue == accountAddress
            }
        )
        for wallet in try fetch(walletDescriptor) {
            delete(wallet)
        }
    }
}
