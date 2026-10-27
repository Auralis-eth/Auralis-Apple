import SwiftData
import AuralisCrypto

@MainActor
enum TokenStorageTestModelContainers {
    static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([TokenHolding.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
