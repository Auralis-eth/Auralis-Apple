@testable import Auralis
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import ReceiptStorage
import SwiftData
import TokenStorage

@MainActor
enum TestSchemas {
    static let primary = PrimaryStoreSchema.schema
    static let packagePrimary = Schema([
        EOAccount.self,
        NFT.self,
        Tag.self,
        StoredReceipt.self,
        Playlist.self,
        MusicLibraryItem.self,
        TokenHolding.self,
        SearchHistoryRecord.self
    ])
    static let receipts = Schema([StoredReceipt.self])
    static let tokens = Schema([TokenHolding.self])
    static let searchHistory = Schema([SearchHistoryRecord.self])
    static let auraPlay = Schema([Playlist.self, NFT.self, Tag.self, StoredReceipt.self, MusicLibraryItem.self])
}

@MainActor
enum TestModelContainers {
    static func inMemory(_ schema: Schema, undoEnabled: Bool = false) throws -> ModelContainer {
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        if undoEnabled {
            container.mainContext.undoManager = UndoManager()
        }

        return container
    }

    static func primary(undoEnabled: Bool = false) throws -> ModelContainer {
        try inMemory(TestSchemas.primary, undoEnabled: undoEnabled)
    }

    static func primaryStore(undoEnabled: Bool = false) throws -> ModelContainer {
        try primary(undoEnabled: undoEnabled)
    }

    static func packagePrimary(undoEnabled: Bool = false) throws -> ModelContainer {
        try inMemory(TestSchemas.packagePrimary, undoEnabled: undoEnabled)
    }
}
