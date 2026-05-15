import MusicFeature
import SwiftData

@MainActor
enum PreviewModelContainers {
    static func primary() -> ModelContainer {
        do {
            return try ModelContainer(
                for: PrimaryStoreSchema.schema,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Failed to create primary preview model container: \(error.localizedDescription)")
        }
    }

    static func auraPlay() -> ModelContainer {
        do {
            return try AuraPlayModelContainer.make(inMemory: true)
        } catch {
            fatalError("Failed to create AuraPlay preview model container: \(error.localizedDescription)")
        }
    }
}
