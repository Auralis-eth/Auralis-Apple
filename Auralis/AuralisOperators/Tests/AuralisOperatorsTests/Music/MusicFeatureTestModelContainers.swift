import AuralisCrypto
import AuralisOperators
import AuralisReceipts
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
            MusicLibraryItem.self
        ])
    }

    static func receipts() throws -> ModelContainer {
        try inMemory(models: [
            StoredReceipt.self
        ])
    }

    private static func inMemory(models: [any PersistentModel.Type]) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            // `cloudKitDatabase` defaults to `.automatic`, which picks up the host app's iCloud
            // entitlement. These schemas carry unique attributes that CloudKit rejects, so an
            // entitled host turns every container here into a 134060 load failure. `swift test`
            // runs unentitled and cannot surface that, so the opt-out is explicit.
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }
}
