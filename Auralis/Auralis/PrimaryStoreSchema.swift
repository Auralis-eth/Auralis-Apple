import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisOperators
import AuralisReceipts
import SwiftData
import TokenStorage

enum PrimaryStoreSchema {
    static let models: [any PersistentModel.Type] = [
        EOAccount.self,
        NFT.self,
        Tag.self,
        StoredReceipt.self,
        Playlist.self,
        MusicLibraryItem.self,
        TokenHolding.self,
        SearchHistoryRecord.self
    ]

    static let schema = Schema(models)

    /// The only configuration anything should build a primary container with, and it exists to
    /// pass one argument: `cloudKitDatabase: .none`.
    ///
    /// **This app uses CloudKit, and deliberately does not use SwiftData's CloudKit mirroring.**
    /// `ModelConfiguration`'s `cloudKitDatabase` parameter defaults to `.automatic`, which Apple
    /// documents as "enables managed CloudKit sync using the primary ubiquity container from the
    /// app's entitlements" — SwiftData reads `Auralis.entitlements`, finds the first iCloud
    /// container identifier, and takes its presence as instruction to mirror the whole schema.
    ///
    /// That became live the moment the receipt-ledger witness added
    /// `com.apple.developer.icloud-container-identifiers` for `iCloud.ETH.Auralis.Auralis`. The
    /// witness talks to CloudKit through `CKContainer` **directly**
    /// (``CloudKitReceiptLedgerWitness``); it has never wanted SwiftData mirroring. But the
    /// entitlement is app-wide, so every container in the app silently opted in — and this schema
    /// breaks all three of CloudKit's structural rules, so every one of them then failed to load:
    ///
    /// - `CloudKit integration does not support unique constraints` — 17 `@Attribute(.unique)`
    ///   across `EOAccount.address`, `NFT.id`, `StoredReceipt.id`, `Tag.name` and the rest.
    /// - `requires that all attributes be optional, or have a default value set` — most columns.
    /// - `requires that all relationships be optional` / `have an inverse` — `EOAccount.nfts`,
    ///   `Playlist.tracks`, `Tag.nfts`, `NFT.contract`.
    ///
    /// The symptom was `NSCocoaErrorDomain Code=134060` out of every `ModelContainer` initializer,
    /// surfacing as `SwiftDataError.loadIssueModelContainer`: no accounts, no receipts, no library,
    /// no token holdings. Apple's own remedy for this exact situation is the section
    /// *"Disable automatic sync in apps already using CloudKit"*, which says to pass `.none`
    /// explicitly.
    ///
    /// Making the schema CloudKit-compatible is **not** the alternative to reach for. It would mean
    /// dropping every unique constraint — including `StoredReceipt.id`, which the receipt chain's
    /// integrity depends on — to enable a sync feature the app does not offer.
    static func configuration(isStoredInMemoryOnly: Bool = false) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
    }
}
