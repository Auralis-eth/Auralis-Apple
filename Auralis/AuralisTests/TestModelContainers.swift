@testable import Auralis
import Foundation
import SwiftData

@MainActor
enum TestModelContainers {
    static func primary(undoEnabled: Bool = false) throws -> ModelContainer {
        let container = try ModelContainer(
            for: PrimaryStoreSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        if undoEnabled {
            container.mainContext.undoManager = UndoManager()
        }

        return container
    }

    static func primaryStore(undoEnabled: Bool = false) throws -> ModelContainer {
        try primary(undoEnabled: undoEnabled)
    }
}
