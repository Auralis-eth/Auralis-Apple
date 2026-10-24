import Foundation
import SwiftData

public enum AuraPlayModelContainer {
    private static let storeDirectoryName = "AuraPlay"
    private static let storeFileName = "AuraPlay.store"

    public static func make(inMemory: Bool, baseDirectory: URL? = nil) throws -> ModelContainer {
        let schema = Schema(AuraPlaySchema.models)
        // `cloudKitDatabase: .none` on both branches, and it is load-bearing rather than tidy.
        //
        // The parameter defaults to `.automatic`, which Apple documents as enabling managed
        // CloudKit sync using the first iCloud container identifier in the *host app's*
        // entitlements. Auralis gained one of those for the receipt-ledger witness, which talks to
        // CloudKit through `CKContainer` directly and never wanted SwiftData mirroring — but the
        // entitlement is app-wide, so this container silently opted in too and then failed to load
        // with `NSCocoaErrorDomain Code=134060`: the AuraPlay schema has seven `@Attribute(.unique)`
        // columns and a non-optional `AuraPlayPlaylist.items` relationship, and CloudKit permits
        // neither. Every media row, playlist and playback position became unreadable.
        //
        // A package cannot see the host's entitlements, so this cannot be conditional on them; the
        // opt-out has to be unconditional and stated.
        let configuration = if inMemory {
            ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            ModelConfiguration(
                schema: schema,
                url: try storeURL(baseDirectory: baseDirectory),
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
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
