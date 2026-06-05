import AuralisPrimaryModels
import AuralisPrimaryPersistence
import ReceiptStorage
import SwiftData
import TokenStorage

@MainActor
enum AccountStorageTestModelContainers {
    static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([
                EOAccount.self,
                NFT.self,
                Tag.self,
                StoredReceipt.self,
                Playlist.self,
                MusicLibraryItem.self,
                TokenHolding.self,
                SearchHistoryRecord.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
