@testable import Auralis
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

        #expect(missingIdentifiers.isEmpty)
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
