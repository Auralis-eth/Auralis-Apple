@testable import Auralis
import AuralisPrimaryPersistence
import MusicFeature
import Testing

@Suite
struct LocalDataStoragePolicyTests {
    @Test("declares required local data classifications")
    func declaresRequiredLocalDataClassifications() {
        #expect(
            Set(LocalDataClassification.allCases) == [
                .publicIdentifierMetadata,
                .publicPreference,
                .walletMetadata,
                .credential
            ]
        )
    }

    @Test("registers every known persisted identifier in the policy table")
    func registersEveryKnownPersistedIdentifier() {
        let registeredIdentifiers = Set(LocalDataStoragePolicy.decisions.map(\.identifier))
        let missingIdentifiers = LocalDataStoragePolicy.requiredKnownIdentifiers.subtracting(registeredIdentifiers)
        let untrackedIdentifiers = registeredIdentifiers.subtracting(LocalDataStoragePolicy.requiredKnownIdentifiers)

        #expect(missingIdentifiers.isEmpty, "Missing policy decisions: \(missingIdentifiers.sorted())")
        #expect(untrackedIdentifiers.isEmpty, "Policy decisions not marked as required: \(untrackedIdentifiers.sorted())")
    }

    @Test("requires all active SwiftData schema models in the policy table")
    func requiresAllActiveSwiftDataSchemaModels() {
        let activeSchemaIdentifiers = Set(
            PrimaryStoreSchema.models.map { String(describing: $0) }
        ).union(
            AuraPlaySchema.models.map { String(describing: $0) }
        )
        let missingIdentifiers = activeSchemaIdentifiers.subtracting(LocalDataStoragePolicy.requiredKnownIdentifiers)

        #expect(missingIdentifiers.isEmpty, "SwiftData schema models missing from policy requirements: \(missingIdentifiers.sorted())")
    }

    @Test("registers every persisted SwiftData model with a reset phase")
    func registersEveryPersistedSwiftDataModelWithResetPhase() throws {
        for identifier in LocalDataStoragePolicy.persistedSwiftDataModelIdentifiers {
            let decision = try #require(LocalDataStoragePolicy.decision(for: identifier))

            #expect(decision.storage == .swiftData, "\(identifier) must be classified as SwiftData storage")
            #expect(decision.resetPhase != nil, "\(identifier) must declare a privacy reset phase")
        }
    }

    @Test("does not duplicate local data policy identifiers")
    func doesNotDuplicateLocalDataPolicyIdentifiers() {
        let identifiers = LocalDataStoragePolicy.decisions.map(\.identifier)

        #expect(identifiers.count == Set(identifiers).count)
    }

    @Test("maps known persisted values to storage classes")
    func mapsKnownPersistedValuesToStorageClasses() throws {
        let appMode = try #require(LocalDataStoragePolicy.decision(for: ModeState.storageDecisionIdentifier))
        let pinnedItems = try #require(LocalDataStoragePolicy.decision(for: HomePinnedItemsStore.storageDecisionIdentifier))
        let ensCache = try #require(LocalDataStoragePolicy.decision(for: "Auralis.ENSResolutionCache.v1"))
        let receiptIntegrityHeads = try #require(LocalDataStoragePolicy.decision(for: "AuralisReceiptIntegrityHeadService"))
        let searchHistory = try #require(LocalDataStoragePolicy.decision(for: "SearchHistoryRecord"))
        let gasCache = try #require(LocalDataStoragePolicy.decision(for: "ProviderKit.GasPriceCache.shared"))
        let providerClientKey = try #require(LocalDataStoragePolicy.decision(for: "AURALIS_ALCHEMY_API_KEY"))
        let shellSelection = try #require(LocalDataStoragePolicy.decision(for: "auralis.shell.selection.v1"))
        let credentials = try #require(LocalDataStoragePolicy.decision(for: "WalletPasswordService/WalletPasswordAccount"))
        let nftInventory = try #require(LocalDataStoragePolicy.decision(for: "NFT"))
        let nftContract = try #require(LocalDataStoragePolicy.decision(for: String(describing: NFT.Contract.self)))
        let tags = try #require(LocalDataStoragePolicy.decision(for: "Tag"))
        let receipts = try #require(LocalDataStoragePolicy.decision(for: "StoredReceipt"))
        let tokenHoldings = try #require(LocalDataStoragePolicy.decision(for: "TokenHolding"))
        let playlists = try #require(LocalDataStoragePolicy.decision(for: "Playlist"))
        let musicLibrary = try #require(LocalDataStoragePolicy.decision(for: "MusicLibraryItem"))
        let auraPlayMedia = try #require(LocalDataStoragePolicy.decision(for: "AuraPlayMediaItem"))

        #expect(appMode.classification == .publicPreference)
        #expect(appMode.storage == .userDefaults)
        #expect(pinnedItems.classification == .publicPreference)
        #expect(pinnedItems.storage == .userDefaults)
        #expect(ensCache.classification == .publicIdentifierMetadata)
        #expect(ensCache.storage == .userDefaults)
        #expect(ensCache.resetPhase == .supportCaches)
        #expect(receiptIntegrityHeads.classification == .walletMetadata)
        #expect(receiptIntegrityHeads.storage == .keychain)
        #expect(receiptIntegrityHeads.resetPhase == .transactionalStore)
        #expect(searchHistory.classification == .walletMetadata)
        #expect(searchHistory.storage == .swiftData)
        #expect(searchHistory.resetPhase == .transactionalStore)
        #expect(nftInventory.classification == .publicIdentifierMetadata)
        #expect(nftInventory.storage == .swiftData)
        #expect(nftInventory.resetPhase == .transactionalStore)
        #expect(nftContract.classification == .publicIdentifierMetadata)
        #expect(nftContract.storage == .swiftData)
        #expect(nftContract.resetPhase == .transactionalStore)
        #expect(tags.classification == .walletMetadata)
        #expect(tags.storage == .swiftData)
        #expect(tags.resetPhase == .transactionalStore)
        #expect(receipts.classification == .walletMetadata)
        #expect(receipts.storage == .swiftData)
        #expect(receipts.resetPhase == .transactionalStore)
        #expect(tokenHoldings.classification == .walletMetadata)
        #expect(tokenHoldings.storage == .swiftData)
        #expect(tokenHoldings.resetPhase == .transactionalStore)
        #expect(playlists.classification == .walletMetadata)
        #expect(playlists.storage == .swiftData)
        #expect(playlists.resetPhase == .transactionalStore)
        #expect(musicLibrary.classification == .walletMetadata)
        #expect(musicLibrary.storage == .swiftData)
        #expect(musicLibrary.resetPhase == .transactionalStore)
        #expect(auraPlayMedia.classification == .walletMetadata)
        #expect(auraPlayMedia.storage == .swiftData)
        #expect(auraPlayMedia.resetPhase == .auraPlayPersistence)
        #expect(gasCache.classification == .publicIdentifierMetadata)
        #expect(gasCache.storage == .memoryCache)
        #expect(gasCache.resetPhase == .supportCaches)
        #expect(providerClientKey.classification == .publicPreference)
        #expect(providerClientKey.storage == .bundleConfiguration)
        #expect(providerClientKey.resetPhase == nil)
        #expect(shellSelection.classification == .walletMetadata)
        #expect(shellSelection.storage == .keychain)
        #expect(shellSelection.resetPhase == .localPreferences)
        #expect(shellSelection.rationale.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))
        #expect(shellSelection.rationale.contains("ThisDeviceOnly"))
        #expect(credentials.classification == .credential)
        #expect(credentials.storage == .keychain)
    }

    @Test("does not allow shell selection to fall back to UserDefaults")
    func shellSelectionIsProtectedWalletMetadata() {
        let shellSelection = LocalDataStoragePolicy.decision(for: "auralis.shell.selection.v1")

        #expect(shellSelection?.classification == .walletMetadata)
        #expect(shellSelection?.storage == .keychain)
    }
}
