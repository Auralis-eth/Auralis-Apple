import AuralisPrimaryModels
import AuralisPrimaryPersistence
import MusicFeature
import ReceiptStorage
import SwiftData
import TokenStorage

enum PrimaryStoreSchema {
    static let models: [any PersistentModel.Type] = [
        EOAccount.self,
        NFT.self,
        Tag.self,
        StoredReceipt.self,
        Playlist.self,
        MusicLibraryItem.self,
        TokenHolding.self,
        SearchHistoryRecord.self,
    ]

    static let schema = Schema(models)
}
