import Foundation
import SwiftData

enum AppModelContainer {
    private static let storeDirectoryName = "AuraPlay"
    private static let storeFileName = "AuraPlay.store"

    static func make(inMemory: Bool) throws -> ModelContainer {
        let configuration = if inMemory {
            ModelConfiguration(
                schema: Schema(AuraPlaySchemaV1.models),
                isStoredInMemoryOnly: true
            )
        } else {
            ModelConfiguration(
                schema: Schema(AuraPlaySchemaV1.models),
                url: try storeURL()
            )
        }

        return try ModelContainer(
            for: Schema(AuraPlaySchemaV1.models),
            migrationPlan: AuraPlayMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func storeURL() throws -> URL {
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeDirectory = applicationSupportDirectory.appending(path: storeDirectoryName)

        if !FileManager.default.fileExists(atPath: storeDirectory.path()) {
            try FileManager.default.createDirectory(
                at: storeDirectory,
                withIntermediateDirectories: true
            )
        }

        return storeDirectory.appending(path: storeFileName)
    }
}
