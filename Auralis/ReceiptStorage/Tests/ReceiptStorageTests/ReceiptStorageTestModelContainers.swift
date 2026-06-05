import ReceiptStorage
import SwiftData

@MainActor
enum ReceiptStorageTestModelContainers {
    static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([StoredReceipt.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
