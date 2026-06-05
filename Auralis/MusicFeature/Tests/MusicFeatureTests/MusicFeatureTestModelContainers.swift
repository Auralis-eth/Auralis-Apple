import AuralisPrimaryModels
import AuralisPrimaryPersistence
import MusicFeature
import ReceiptStorage
import SwiftData

@MainActor
enum MusicFeatureTestModelContainers {
    static func libraryIndex() throws -> ModelContainer {
        try inMemory(models: [
            NFT.self,
            NFT.Contract.self,
            NFT.Collection.self,
            NFT.Image.self,
            NFT.Raw.self,
            Tag.self,
            StoredReceipt.self,
            MusicLibraryItem.self,
        ])
    }

    static func receipts() throws -> ModelContainer {
        try inMemory(models: [
            StoredReceipt.self,
        ])
    }

    private static func inMemory(models: [any PersistentModel.Type]) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
