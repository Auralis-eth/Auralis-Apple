import SwiftData

@MainActor
enum SwiftDataAdaptersTestModelContainers {
    static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema([SwiftDataAdapterFixture.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        return ModelContext(container)
    }
}
