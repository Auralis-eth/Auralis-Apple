@testable import Auralis
import AuralisPrimaryPersistence
import Foundation
import MusicFeature
import ReceiptStorage
import SwiftData
import TokenStorage

@MainActor
enum TestSchemas {
    static let primary = PrimaryStoreSchema.schema
    static let packagePrimary = Schema([
        EOAccount.self,
        NFT.self,
        Tag.self,
        StoredReceipt.self,
        Playlist.self,
        MusicLibraryItem.self,
        TokenHolding.self,
        SearchHistoryRecord.self
    ])
    static let receipts = Schema([StoredReceipt.self])
    static let tokens = Schema([TokenHolding.self])
    static let searchHistory = Schema([SearchHistoryRecord.self])
    static let auraPlay = Schema([Playlist.self, NFT.self, Tag.self, StoredReceipt.self, MusicLibraryItem.self])
}

@MainActor
enum TestModelContainers {
    static func inMemory(_ schema: Schema, undoEnabled: Bool = false) throws -> ModelContainer {
        let container = try ModelContainer(
            for: schema,
            // `schema:` and `cloudKitDatabase: .none`, both of which were missing and both of which
            // matter.
            //
            // The CloudKit opt-out is why this line is commented: these tests are app-hosted, so
            // they run inside the Auralis bundle and inherit its entitlements — including the
            // iCloud container the receipt-ledger witness added. `cloudKitDatabase` defaults to
            // `.automatic`, so every container built here tried to mirror to CloudKit and failed
            // with `NSCocoaErrorDomain Code=134060`, taking 150 tests down at once with
            // `SwiftDataError.loadIssueModelContainer`. Package suites run under `swift test` with
            // no entitlement and stayed green throughout, which is exactly why this needed the app
            // plan to surface. See `PrimaryStoreSchema.configuration(isStoredInMemoryOnly:)`.
            //
            // Passing `schema:` as well so the configuration describes the same models the
            // container is built for, rather than relying on the container to reconcile them.
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )

        if undoEnabled {
            container.mainContext.undoManager = UndoManager()
        }

        return container
    }

    static func primary(undoEnabled: Bool = false) throws -> ModelContainer {
        try inMemory(TestSchemas.primary, undoEnabled: undoEnabled)
    }

    static func primaryStore(undoEnabled: Bool = false) throws -> ModelContainer {
        try primary(undoEnabled: undoEnabled)
    }

    static func packagePrimary(undoEnabled: Bool = false) throws -> ModelContainer {
        try inMemory(TestSchemas.packagePrimary, undoEnabled: undoEnabled)
    }
}
