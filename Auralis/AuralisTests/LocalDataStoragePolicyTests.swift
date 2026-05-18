@testable import Auralis
import Testing

@Suite
struct LocalDataStoragePolicyTests {
    @Test("declares required local data classifications")
    func declaresRequiredLocalDataClassifications() {
        #expect(Set(LocalDataClassification.allCases) == [.publicPreference, .walletMetadata, .credential])
    }

    @Test("maps known persisted values to storage classes")
    func mapsKnownPersistedValuesToStorageClasses() throws {
        let appMode = try #require(LocalDataStoragePolicy.decision(for: ModeState.storageDecisionIdentifier))
        let pinnedItems = try #require(LocalDataStoragePolicy.decision(for: HomePinnedItemsStore.storageDecisionIdentifier))
        let shellSelection = try #require(LocalDataStoragePolicy.decision(for: "auralis.shell.selection.v1"))
        let credentials = try #require(LocalDataStoragePolicy.decision(for: "WalletPasswordService/WalletPasswordAccount"))

        #expect(appMode.classification == .publicPreference)
        #expect(appMode.storage == .userDefaults)
        #expect(pinnedItems.classification == .publicPreference)
        #expect(pinnedItems.storage == .userDefaults)
        #expect(shellSelection.classification == .walletMetadata)
        #expect(shellSelection.storage == .keychain)
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
