import Foundation
import SwiftData

enum AppModelContainer {
    private static let storeDirectoryName = "AuraPlay"
    private static let storeFileName = "AuraPlay.store"

    static func make(inMemory: Bool) throws -> ModelContainer {
        let configuration = if inMemory {
            ModelConfiguration(
                schema: Schema(AuraPlaySchemaV2.models),
                isStoredInMemoryOnly: true
            )
        } else {
            ModelConfiguration(
                schema: Schema(AuraPlaySchemaV2.models),
                url: try storeURL()
            )
        }

        return try ModelContainer(
            for: Schema(AuraPlaySchemaV2.models),
            migrationPlan: AuraPlayMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func storeURL() throws -> URL {
        try storeURL(baseDirectory: nil)
    }

    static func storeURL(baseDirectory: URL?) throws -> URL {
        let applicationSupportDirectory = try baseDirectory ?? FileManager.default.url(
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

    static func resetStoreFiles(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) throws {
        let primaryStoreURL = try storeURL(baseDirectory: baseDirectory)
        let candidateURLs = [
            primaryStoreURL,
            primaryStoreURL.appendingPathExtension("shm"),
            primaryStoreURL.appendingPathExtension("wal"),
        ]

        for candidateURL in candidateURLs where fileManager.fileExists(atPath: candidateURL.path()) {
            try fileManager.removeItem(at: candidateURL)
        }
    }
}
