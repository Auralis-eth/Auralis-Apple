import Foundation
import SwiftData

public enum AuraPlayModelContainer {
    private static let storeDirectoryName = "AuraPlay"
    private static let storeFileName = "AuraPlay.store"

    public static func make(inMemory: Bool, baseDirectory: URL? = nil) throws -> ModelContainer {
        let schema = Schema(AuraPlaySchema.models)
        let configuration = if inMemory {
            ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        } else {
            ModelConfiguration(
                schema: schema,
                url: try storeURL(baseDirectory: baseDirectory)
            )
        }

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private static func storeURL() throws -> URL {
        try storeURL(baseDirectory: nil)
    }

    public static func storeURL(baseDirectory: URL?) throws -> URL {
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

    public static func resetStoreFiles(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) throws {
        let primaryStoreURL = try storeURL(baseDirectory: baseDirectory)
        let candidateURLs = [
            primaryStoreURL,
            URL(filePath: primaryStoreURL.path() + "-shm"),
            URL(filePath: primaryStoreURL.path() + "-wal")
        ]

        for candidateURL in candidateURLs where fileManager.fileExists(atPath: candidateURL.path()) {
            try fileManager.removeItem(at: candidateURL)
        }
    }
}
