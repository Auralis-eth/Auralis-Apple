import SwiftData

@MainActor
enum PreviewModelContainers {
    private static var primaryStoreModels: [any PersistentModel.Type] {
        [
            EOAccount.self,
            NFT.self,
            Tag.self,
            StoredReceipt.self,
            Playlist.self,
            MusicLibraryItem.self,
            TokenHolding.self,
            SearchHistoryRecord.self,
        ]
    }

    static func primary() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Schema(primaryStoreModels),
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Failed to create primary preview model container: \(error.localizedDescription)")
        }
    }

    static func auraPlay() -> ModelContainer {
        do {
            return try AppModelContainer.make(inMemory: true)
        } catch {
            fatalError("Failed to create AuraPlay preview model container: \(error.localizedDescription)")
        }
    }
}
