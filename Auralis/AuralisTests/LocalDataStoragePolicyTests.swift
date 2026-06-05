@testable import Auralis
import AuralisPrimaryPersistence
import AuralisTestSupport
import MusicFeature
import Testing

@Suite(.tags(.architecture, .privacy))
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

    @Test(
        "registers every persisted SwiftData model with a reset phase",
        arguments: LocalDataStoragePolicy.persistedSwiftDataModelIdentifiers
    )
    func registersEveryPersistedSwiftDataModelWithResetPhase(identifier: String) throws {
        let decision = try #require(LocalDataStoragePolicy.decision(for: identifier))

        #expect(decision.storage == .swiftData, "\(identifier) must be classified as SwiftData storage")
        _ = try #require(decision.resetPhase, "\(identifier) must declare a privacy reset phase")
    }

    @Test("does not duplicate local data policy identifiers")
    func doesNotDuplicateLocalDataPolicyIdentifiers() {
        let identifiers = LocalDataStoragePolicy.decisions.map(\.identifier)

        #expect(identifiers.count == Set(identifiers).count)
    }

    struct PolicyExpectation: Sendable, CustomStringConvertible {
        let identifier: String
        let classification: LocalDataClassification
        let storage: LocalDataStorage
        let resetPhase: PrivacyResetPhase?

        var description: String { identifier }
    }

    static let policyExpectations: [PolicyExpectation] = [
        .init(identifier: ModeState.storageDecisionIdentifier, classification: .publicPreference, storage: .userDefaults, resetPhase: .localPreferences),
        .init(identifier: HomePinnedItemsStore.storageDecisionIdentifier, classification: .publicPreference, storage: .userDefaults, resetPhase: .localPreferences),
        .init(identifier: "Auralis.ENSResolutionCache.v1", classification: .publicIdentifierMetadata, storage: .userDefaults, resetPhase: .supportCaches),
        .init(identifier: "AuralisReceiptIntegrityHeadService", classification: .walletMetadata, storage: .keychain, resetPhase: .transactionalStore),
        .init(identifier: "SearchHistoryRecord", classification: .walletMetadata, storage: .swiftData, resetPhase: .transactionalStore),
        .init(identifier: "ProviderKit.GasPriceCache.shared", classification: .publicIdentifierMetadata, storage: .memoryCache, resetPhase: .supportCaches),
        .init(identifier: "AURALIS_ALCHEMY_API_KEY", classification: .publicPreference, storage: .bundleConfiguration, resetPhase: nil),
        .init(identifier: "WalletPasswordService/WalletPasswordAccount", classification: .credential, storage: .keychain, resetPhase: .credentialStore),
        .init(identifier: "NFT", classification: .publicIdentifierMetadata, storage: .swiftData, resetPhase: .transactionalStore),
        .init(identifier: String(describing: NFT.Contract.self), classification: .publicIdentifierMetadata, storage: .swiftData, resetPhase: .transactionalStore),
        .init(identifier: "Tag", classification: .walletMetadata, storage: .swiftData, resetPhase: .transactionalStore),
        .init(identifier: "StoredReceipt", classification: .walletMetadata, storage: .swiftData, resetPhase: .transactionalStore),
        .init(identifier: "TokenHolding", classification: .walletMetadata, storage: .swiftData, resetPhase: .transactionalStore),
        .init(identifier: "Playlist", classification: .walletMetadata, storage: .swiftData, resetPhase: .transactionalStore),
        .init(identifier: "MusicLibraryItem", classification: .walletMetadata, storage: .swiftData, resetPhase: .transactionalStore),
        .init(identifier: "AuraPlayMediaItem", classification: .walletMetadata, storage: .swiftData, resetPhase: .auraPlayPersistence),
        .init(identifier: "auralis.shell.selection.v1", classification: .walletMetadata, storage: .keychain, resetPhase: .localPreferences)
    ]

    @Test(
        "known persisted identifiers map to expected storage class and reset phase",
        arguments: LocalDataStoragePolicyTests.policyExpectations
    )
    func knownPersistedIdentifierMatchesExpectedDecision(expectation: PolicyExpectation) throws {
        let decision = try #require(
            LocalDataStoragePolicy.decision(for: expectation.identifier),
            "Missing policy decision for \(expectation.identifier)"
        )

        #expect(decision.classification == expectation.classification)
        #expect(decision.storage == expectation.storage)
        #expect(decision.resetPhase == expectation.resetPhase)
    }

    @Test("shell selection rationale documents the keychain accessibility class")
    func shellSelectionRationaleDocumentsKeychainAccessibility() throws {
        let shellSelection = try #require(LocalDataStoragePolicy.decision(for: "auralis.shell.selection.v1"))

        #expect(shellSelection.rationale.contains("kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"))
        #expect(shellSelection.rationale.contains("ThisDeviceOnly"))
    }

    @Test("does not allow shell selection to fall back to UserDefaults")
    func shellSelectionIsProtectedWalletMetadata() throws {
        let shellSelection = LocalDataStoragePolicy.decision(for: "auralis.shell.selection.v1")

        #expect(try #require(shellSelection).classification == .walletMetadata)
        #expect(try #require(shellSelection).storage == .keychain)
    }
}
