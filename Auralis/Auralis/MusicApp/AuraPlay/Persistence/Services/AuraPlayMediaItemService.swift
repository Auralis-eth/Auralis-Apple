import AuralisPrimaryModels
import Foundation
import SwiftData

@ModelActor
actor AuraPlayMediaItemService {
    func replaceAll(
        walletID: String,
        requests: [AuraPlayMediaItemUpsertRequest],
        syncedAt: Date
    ) throws {
        let wallet = try fetchWallet(id: walletID)
        let existingItems = try fetchScopedItems(walletID: walletID)
        var existingByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        var retainedIDs: Set<String> = []

        for request in requests {
            retainedIDs.insert(request.sourceNFTID)

            let item = existingByID[request.sourceNFTID] ?? {
                let newItem = AuraPlayMediaItem(
                    walletID: walletID,
                    sourceNFTID: request.sourceNFTID,
                    accountAddressRawValue: request.accountAddressRawValue,
                    chain: request.chain,
                    contractAddressRawValue: request.contractAddressRawValue,
                    tokenID: request.tokenID,
                    tokenType: request.tokenType,
                    title: request.title,
                    artistName: request.artistName,
                    collectionName: request.collectionName,
                    normalizedTitleKey: request.normalizedTitleKey,
                    normalizedArtistKey: request.normalizedArtistKey,
                    normalizedCollectionKey: request.normalizedCollectionKey,
                    artworkURLString: request.artworkURLString,
                    playbackURLString: request.playbackURLString,
                    contentType: request.contentType,
                    sourceUpdatedAtRawValue: request.sourceUpdatedAtRawValue,
                    hasArtwork: request.hasArtwork,
                    hasAudio: request.hasAudio,
                    isPlayable: request.isPlayable,
                    isSearchable: request.isSearchable,
                    createdAt: syncedAt,
                    updatedAt: syncedAt
                )
                newItem.wallet = wallet
                modelContext.insert(newItem)
                existingByID[request.sourceNFTID] = newItem
                return newItem
            }()

            item.walletID = walletID
            item.accountAddressRawValue = request.accountAddressRawValue
            item.chain = request.chain
            item.contractAddressRawValue = request.contractAddressRawValue
            item.tokenID = request.tokenID
            item.tokenType = request.tokenType
            item.title = request.title
            item.artistName = request.artistName
            item.collectionName = request.collectionName
            item.normalizedTitleKey = request.normalizedTitleKey
            item.normalizedArtistKey = request.normalizedArtistKey
            item.normalizedCollectionKey = request.normalizedCollectionKey
            item.artworkURLString = request.artworkURLString
            item.playbackURLString = request.playbackURLString
            item.contentType = request.contentType
            item.sourceUpdatedAtRawValue = request.sourceUpdatedAtRawValue
            item.hasArtwork = request.hasArtwork
            item.hasAudio = request.hasAudio
            item.isPlayable = request.isPlayable
            item.isSearchable = request.isSearchable
            item.wallet = wallet
            item.updatedAt = syncedAt
        }

        for item in existingItems where !retainedIDs.contains(item.id) {
            modelContext.delete(item)
        }

        try modelContext.save()
    }

    private func fetchWallet(id: String) throws -> AuraPlayWallet? {
        let descriptor = FetchDescriptor<AuraPlayWallet>(
            predicate: #Predicate<AuraPlayWallet> { wallet in
                wallet.id == id
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchScopedItems(walletID: String) throws -> [AuraPlayMediaItem] {
        let descriptor = FetchDescriptor<AuraPlayMediaItem>(
            predicate: #Predicate<AuraPlayMediaItem> { item in
                item.walletID == walletID
            }
        )
        return try modelContext.fetch(descriptor)
    }
}
