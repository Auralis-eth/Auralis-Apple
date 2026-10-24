import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ReceiptStorage
import SwiftData
import TokenStorage

@MainActor
enum AccountStorageTestModelContainers {
    static func context(undoEnabled: Bool = false) throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([
                EOAccount.self,
                NFT.self,
                Tag.self,
                StoredReceipt.self,
                Playlist.self,
                TokenHolding.self,
            ]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        let context = ModelContext(container)
        if undoEnabled {
            context.undoManager = UndoManager()
        }
        return context
    }
}
