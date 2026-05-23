import ReceiptsCore
import ReceiptStorage
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
@testable import Auralis
import AccountStorage
import AccountsCore
import ENS
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuralisShellCore
import Foundation
import MusicFeature
import SwiftData
import Testing
import TokenStorage

@MainActor
@Suite
struct PrivacyResetServiceTests {
    @Test("resetLocalPrivacyData clears persisted search history rows")
    func resetLocalPrivacyDataClearsSearchHistory() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let ensCacheResetService = RecordingENSCacheResetService()
        let transactionalResetService = SwiftDataTransactionalPrivacyResetService(
            modelContainer: context.container
        )
        let auraPlayPersistenceResetService = RecordingAuraPlayPersistenceResetService()
        let credentialResetService = RecordingCredentialPrivacyResetter()
        let selectionPersistence = RecordingShellSelectionPersistence()
        let pinnedItemsStore = makeIsolatedPinnedItemsStore()
        let service = PrivacyResetService(
            transactionalResetService: transactionalResetService,
            ensCacheResetService: ensCacheResetService,
            auraPlayPersistenceResetService: auraPlayPersistenceResetService,
            credentialResetService: credentialResetService,
            selectionPersistence: selectionPersistence,
            homePinnedItemsStore: pinnedItemsStore
        )
        let searchHistoryStore = SearchHistoryStore(modelContext: context)
        let tokenHoldingsStore = SwiftDataTokenHoldingsStore(modelContext: context)
        let receiptStore = ReceiptStores.live(modelContext: context)

        try await searchHistoryStore.recordCommittedQuery("Moonpunks", accountAddress: nil)
        try await searchHistoryStore.recordCommittedQuery("USDC", accountAddress: "0x1111111111111111111111111111111111111111")
        try await tokenHoldingsStore.upsertNativeHolding(
            accountAddress: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet,
            amountDisplay: "1.25",
            updatedAt: .now
        )
        try pinnedItemsStore.togglePin(
            .openNews,
            accountAddress: "0x1111111111111111111111111111111111111111"
        )
        context.insert(makeFixtureNFT(tokenId: "moon-1"))
        context.insert(makeFixtureMusicLibraryItem(id: "track-1", sourceNFTID: "music-source-1"))
        context.insert(try AuralisPrimaryPersistence.Tag(name: "Local Favorite"))
        try context.save()
        _ = try await receiptStore.append(
            ReceiptDraft(
                trigger: "fixture-reset",
                scope: "tests",
                summary: "fixture",
                provenance: "local",
                isSuccess: true,
                details: ReceiptPayload(values: [:])
            )
        )

        try await service.resetLocalPrivacyData()

        #expect(searchHistoryStore.entries(for: nil).isEmpty)
        #expect(searchHistoryStore.entries(for: "0x1111111111111111111111111111111111111111").isEmpty)
        #expect(await ensCacheResetService.resetCount() == 1)
        #expect(await auraPlayPersistenceResetService.resetCount() == 1)
        #expect(await credentialResetService.clearCount() == 1)
        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MusicLibraryItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AuralisPrimaryPersistence.Tag>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Contract>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Collection>()).isEmpty)
        #expect(selectionPersistence.clearSelectionCallCount == 1)
        #expect(pinnedItemsStore.pinnedActions(for: "0x1111111111111111111111111111111111111111").isEmpty)
    }

    @Test("privacy reset clears persisted ENS public identifier mappings")
    func resetLocalPrivacyDataClearsENSMappings() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let storageKey = "PrivacyResetServiceTests.ens-cache.\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: storageKey)
        defer {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        let cacheStore = ENSResolutionCacheStore(storageKey: storageKey)
        let service = PrivacyResetService(
            transactionalResetService: SwiftDataTransactionalPrivacyResetService(
                modelContainer: context.container
            ),
            ensCacheResetService: ENSCacheResetService(cacheStore: cacheStore),
            auraPlayPersistenceResetService: RecordingAuraPlayPersistenceResetService(),
            credentialResetService: RecordingCredentialPrivacyResetter(),
            selectionPersistence: RecordingShellSelectionPersistence(),
            homePinnedItemsStore: makeIsolatedPinnedItemsStore()
        )

        await cacheStore.storeForwardResolution(
            ENSForwardCacheEntry(
                ensName: "vitalik.eth",
                address: "0x1234567890abcdef1234567890abcdef12345678",
                fetchedAt: .now
            )
        )
        await cacheStore.storeReverseResolution(
            ENSReverseCacheEntry(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                ensName: "vitalik.eth",
                isForwardVerified: true,
                fetchedAt: .now
            )
        )
        #expect(UserDefaults.standard.data(forKey: storageKey) != nil)

        try await service.resetLocalPrivacyData()

        #expect(await cacheStore.cachedForwardResolution(forENS: "vitalik.eth") == nil)
        #expect(
            await cacheStore.cachedReverseResolution(
                forAddress: "0x1234567890abcdef1234567890abcdef12345678"
            ) == nil
        )
        #expect(UserDefaults.standard.data(forKey: storageKey) == nil)
    }

    @Test("removing an account purges only NFTs scoped to that account")
    func accountRemovalPurgesScopedNFTs() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let store = SwiftDataAccountStore(modelContext: context)

        let removed = try await store.createWatchAccount(
            from: "0x1010101010101010101010101010101010101010",
            now: Date(timeIntervalSince1970: 100)
        )
        let preserved = try await store.createWatchAccount(
            from: "0x2020202020202020202020202020202020202020",
            now: Date(timeIntervalSince1970: 200)
        )

        context.insert(makeFixtureNFT(tokenId: "removed-1", accountAddress: removed.address))
        context.insert(makeFixtureMusicLibraryItem(
            id: "removed-track-1",
            sourceNFTID: "removed-source-1",
            accountAddressRawValue: removed.address
        ))
        removed.markAuraPlaySynced(on: .ethMainnet, at: .now)
        context.insert(try makeFixtureStoredReceipt(accountAddress: removed.address))
        try await SearchHistoryStore(modelContext: context).recordCommittedQuery("Removed Scope", accountAddress: removed.address)
        try await SwiftDataTokenHoldingsStore(modelContext: context).upsertNativeHolding(
            accountAddress: removed.address,
            chain: .ethMainnet,
            amountDisplay: "4.2",
            updatedAt: .now
        )
        context.insert(makeFixtureNFT(
            tokenId: "preserved-1",
            accountAddress: preserved.address,
            contractAddress: "0x9999999999999999999999999999999999999999"
        ))
        context.insert(makeFixtureMusicLibraryItem(
            id: "preserved-track-1",
            sourceNFTID: "preserved-source-1",
            accountAddressRawValue: preserved.address
        ))
        preserved.markAuraPlaySynced(on: .ethMainnet, at: .now)
        context.insert(try makeFixtureStoredReceipt(accountAddress: preserved.address))
        try context.save()

        _ = try await store.removeAccount(
            address: removed.address,
            activeAddress: removed.address
        )

        let remainingNFTs = try context.fetch(FetchDescriptor<NFT>())
        let remainingHoldings = try context.fetch(FetchDescriptor<TokenHolding>())
        let remainingMusicItems = try context.fetch(FetchDescriptor<MusicLibraryItem>())
        let remainingReceipts = try context.fetch(FetchDescriptor<StoredReceipt>())
        let remainingAccounts = try context.fetch(FetchDescriptor<EOAccount>())
        #expect(!remainingNFTs.contains(where: { $0.accountAddressRawValue == removed.address }))
        #expect(remainingNFTs.contains(where: { $0.accountAddressRawValue == preserved.address }))
        #expect(!remainingHoldings.contains(where: { $0.accountAddressRawValue == removed.address }))
        #expect(!remainingMusicItems.contains(where: { $0.accountAddressRawValue == removed.address }))
        #expect(remainingMusicItems.contains(where: { $0.accountAddressRawValue == preserved.address }))
        #expect(remainingReceipts.contains(where: { $0.accountAddress == removed.address }))
        #expect(remainingReceipts.contains(where: { $0.accountAddress == preserved.address }))
        #expect(remainingAccounts.contains(where: { $0.address == preserved.address && $0.auraPlayLastSyncedAt(for: .ethMainnet) != nil }))
        #expect(SearchHistoryStore(modelContext: context).entries(for: removed.address).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Contract>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT.Collection>()).count == 1)
    }

    @Test("overwriting an account purges previously persisted NFTs for that account")
    func accountOverwritePurgesScopedNFTs() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let store = SwiftDataAccountStore(modelContext: context)

        let overwritten = try await store.createWatchAccount(
            from: "0x3030303030303030303030303030303030303030",
            now: Date(timeIntervalSince1970: 100)
        )
        let other = try await store.createWatchAccount(
            from: "0x4040404040404040404040404040404040404040",
            now: Date(timeIntervalSince1970: 200)
        )

        context.insert(makeFixtureNFT(tokenId: "stale-overwrite", accountAddress: overwritten.address))
        context.insert(makeFixtureMusicLibraryItem(
            id: "overwrite-track-1",
            sourceNFTID: "overwrite-source-1",
            accountAddressRawValue: overwritten.address
        ))
        overwritten.markAuraPlaySynced(on: .ethMainnet, at: .now)
        context.insert(try makeFixtureStoredReceipt(accountAddress: overwritten.address))
        try await SearchHistoryStore(modelContext: context).recordCommittedQuery("Overwrite Scope", accountAddress: overwritten.address)
        try await SwiftDataTokenHoldingsStore(modelContext: context).upsertNativeHolding(
            accountAddress: overwritten.address,
            chain: .ethMainnet,
            amountDisplay: "9.9",
            updatedAt: .now
        )
        context.insert(makeFixtureNFT(
            tokenId: "keep-other",
            accountAddress: other.address,
            contractAddress: "0x8888888888888888888888888888888888888888"
        ))
        context.insert(makeFixtureMusicLibraryItem(
            id: "keep-other-track-1",
            sourceNFTID: "keep-other-source-1",
            accountAddressRawValue: other.address
        ))
        other.markAuraPlaySynced(on: .ethMainnet, at: .now)
        context.insert(try makeFixtureStoredReceipt(accountAddress: other.address))
        try context.save()

        _ = try await store.createWatchAccount(
            from: overwritten.address,
            source: .qrScan,
            overwriteExisting: true,
            now: Date(timeIntervalSince1970: 300)
        )

        let persistedNFTs = try context.fetch(FetchDescriptor<NFT>())
        let persistedHoldings = try context.fetch(FetchDescriptor<TokenHolding>())
        let persistedMusicItems = try context.fetch(FetchDescriptor<MusicLibraryItem>())
        let persistedReceipts = try context.fetch(FetchDescriptor<StoredReceipt>())
        let persistedAccounts = try context.fetch(FetchDescriptor<EOAccount>())
        #expect(!persistedNFTs.contains(where: { $0.accountAddressRawValue == overwritten.address }))
        #expect(persistedNFTs.contains(where: { $0.accountAddressRawValue == other.address }))
        #expect(!persistedHoldings.contains(where: { $0.accountAddressRawValue == overwritten.address }))
        #expect(!persistedMusicItems.contains(where: { $0.accountAddressRawValue == overwritten.address }))
        #expect(persistedMusicItems.contains(where: { $0.accountAddressRawValue == other.address }))
        #expect(persistedReceipts.contains(where: { $0.accountAddress == overwritten.address }))
        #expect(persistedReceipts.contains(where: { $0.accountAddress == other.address }))
        #expect(persistedAccounts.contains(where: { $0.address == overwritten.address && $0.auraPlayLastSyncedAt(for: .ethMainnet) == nil }))
        #expect(persistedAccounts.contains(where: { $0.address == other.address && $0.auraPlayLastSyncedAt(for: .ethMainnet) != nil }))
        #expect(SearchHistoryStore(modelContext: context).entries(for: overwritten.address).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Contract>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT.Collection>()).count == 1)
    }

    @Test("logout cleanup clears active shell support data while preserving accounts when requested")
    func logoutCleanupClearsShellSupportData() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)

        let preservedAccount = EOAccount(
            address: "0x1111111111111111111111111111111111111111",
            access: .readonly,
            name: "Preserved"
        )
        context.insert(preservedAccount)
        context.insert(makeFixtureNFT(tokenId: "logout-track", accountAddress: preservedAccount.address))
        context.insert(makeFixtureMusicLibraryItem(
            id: "logout-library-item",
            sourceNFTID: "logout-source-1",
            accountAddressRawValue: preservedAccount.address
        ))
        preservedAccount.markAuraPlaySynced(on: .ethMainnet, at: .now)
        context.insert(try makeFixtureStoredReceipt(accountAddress: preservedAccount.address))
        try await SearchHistoryStore(modelContext: context).recordCommittedQuery(
            "Logout Scope",
            accountAddress: preservedAccount.address
        )
        try await SwiftDataTokenHoldingsStore(modelContext: context).upsertNativeHolding(
            accountAddress: preservedAccount.address,
            chain: .ethMainnet,
            amountDisplay: "1.0",
            updatedAt: .now
        )
        let cleanupService = LogoutCleanupService(modelContext: context)

        try cleanupService.clearLocalDataForLogout(
            plan: HomeLogoutPlan(
                shouldDeleteNFTs: true,
                shouldDeleteAccounts: false,
                shouldDeleteTags: true,
                nextCurrentAddress: ""
            )
        )

        #expect(try context.fetch(FetchDescriptor<EOAccount>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MusicLibraryItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SearchHistoryRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Playlist>()).isEmpty)
        let remainingAccount = try #require(context.fetch(FetchDescriptor<EOAccount>()).first)
        #expect(remainingAccount.auraPlayLastSyncedAt(for: .ethMainnet) == nil)
    }

    @Test("AuraPlay store reset removes separate persisted store files when no live container is available")
    func auraPlayStoreResetRemovesPersistedFiles() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let storeURL = try AuraPlayModelContainer.storeURL(baseDirectory: temporaryDirectory)
        let shmURL = storeURL.appendingPathExtension("shm")
        let walURL = storeURL.appendingPathExtension("wal")
        FileManager.default.createFile(atPath: storeURL.path(), contents: Data("store".utf8))
        FileManager.default.createFile(atPath: shmURL.path(), contents: Data("shm".utf8))
        FileManager.default.createFile(atPath: walURL.path(), contents: Data("wal".utf8))

        let service = AuraPlayStoreResetService(
            fileManager: .default,
            baseDirectory: temporaryDirectory
        )

        try await service.resetAuraPlayPersistence()

        #expect(FileManager.default.fileExists(atPath: storeURL.path()) == false)
        #expect(FileManager.default.fileExists(atPath: shmURL.path()) == false)
        #expect(FileManager.default.fileExists(atPath: walURL.path()) == false)
    }

    @Test("token holdings persistence rejects empty account scope instead of silently succeeding")
    func tokenHoldingsStoreRejectsEmptyAccountScope() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let store = SwiftDataTokenHoldingsStore(modelContext: context)

        await #expect(throws: TokenHoldingsStoreError.invalidAccountAddress("   ")) {
            try await store.upsertNativeHolding(
                accountAddress: "   ",
                chain: .ethMainnet,
                amountDisplay: "1.25",
                updatedAt: .now
            )
        }

        await #expect(throws: TokenHoldingsStoreError.invalidAccountAddress("")) {
            try await store.replaceERC20Holdings(
                accountAddress: "",
                chain: .ethMainnet,
                holdings: []
            )
        }

        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
    }

    @Test("privacy reset reports partial completion after transactional data is already committed")
    func resetLocalPrivacyDataSurfacesPartialCompletion() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let service = PrivacyResetService(
            transactionalResetService: SwiftDataTransactionalPrivacyResetService(
                modelContainer: context.container
            ),
            ensCacheResetService: RecordingENSCacheResetService(),
            auraPlayPersistenceResetService: FailingAuraPlayPersistenceResetService(),
            credentialResetService: RecordingCredentialPrivacyResetter(),
            selectionPersistence: RecordingShellSelectionPersistence(),
            homePinnedItemsStore: makeIsolatedPinnedItemsStore()
        )
        let searchHistoryStore = SearchHistoryStore(modelContext: context)

        try await searchHistoryStore.recordCommittedQuery("Partial", accountAddress: nil)

        await #expect {
            try await service.resetLocalPrivacyData()
        } throws: { error in
            guard case LocalDataResetError.phaseFailed(let phase, let completedPhases, _) = error else {
                return false
            }
            return phase == .auraPlayPersistence
                && completedPhases == [.transactionalStore, .supportCaches]
        }

        #expect(searchHistoryStore.entries(for: nil).isEmpty)
    }

    @Test("privacy reset can be retried safely after a later phase fails")
    func resetLocalPrivacyDataCanRetryAfterLaterPhaseFailure() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let ensCacheResetService = RecordingENSCacheResetService()
        let auraPlayPersistenceResetService = FailingOnceAuraPlayPersistenceResetService()
        let selectionPersistence = RecordingShellSelectionPersistence()
        let pinnedItemsStore = makeIsolatedPinnedItemsStore()
        let service = PrivacyResetService(
            transactionalResetService: SwiftDataTransactionalPrivacyResetService(
                modelContainer: context.container
            ),
            ensCacheResetService: ensCacheResetService,
            auraPlayPersistenceResetService: auraPlayPersistenceResetService,
            credentialResetService: RecordingCredentialPrivacyResetter(),
            selectionPersistence: selectionPersistence,
            homePinnedItemsStore: pinnedItemsStore
        )
        let searchHistoryStore = SearchHistoryStore(modelContext: context)
        let tokenHoldingsStore = SwiftDataTokenHoldingsStore(modelContext: context)

        try await searchHistoryStore.recordCommittedQuery("Retry", accountAddress: nil)
        try await tokenHoldingsStore.upsertNativeHolding(
            accountAddress: "0x1111111111111111111111111111111111111111",
            chain: .ethMainnet,
            amountDisplay: "2.5",
            updatedAt: .now
        )
        try pinnedItemsStore.togglePin(
            .openNews,
            accountAddress: "0x1111111111111111111111111111111111111111"
        )

        await #expect {
            try await service.resetLocalPrivacyData()
        } throws: { error in
            guard case LocalDataResetError.phaseFailed(let phase, let completedPhases, _) = error else {
                return false
            }
            return phase == .auraPlayPersistence
                && completedPhases == [.transactionalStore, .supportCaches]
        }

        try await service.resetLocalPrivacyData()

        #expect(searchHistoryStore.entries(for: nil).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
        #expect(await auraPlayPersistenceResetService.attemptCount() == 2)
        #expect(await ensCacheResetService.resetCount() == 2)
        #expect(selectionPersistence.clearSelectionCallCount == 1)
        #expect(pinnedItemsStore.pinnedActions(for: "0x1111111111111111111111111111111111111111").isEmpty)
    }

    @Test("privacy reset surfaces credential clearing failures as typed phase errors")
    func resetLocalPrivacyDataFailsWhenCredentialClearFails() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let service = PrivacyResetService(
            transactionalResetService: SwiftDataTransactionalPrivacyResetService(
                modelContainer: context.container
            ),
            ensCacheResetService: RecordingENSCacheResetService(),
            auraPlayPersistenceResetService: RecordingAuraPlayPersistenceResetService(),
            credentialResetService: FailingCredentialPrivacyResetter(),
            selectionPersistence: RecordingShellSelectionPersistence(),
            homePinnedItemsStore: makeIsolatedPinnedItemsStore()
        )

        await #expect {
            try await service.resetLocalPrivacyData()
        } throws: { error in
            guard case LocalDataResetError.phaseFailed(let phase, let completedPhases, _) = error else {
                return false
            }
            return phase == .credentialStore
                && completedPhases == [.transactionalStore, .supportCaches, .auraPlayPersistence]
        }
    }

    @Test("privacy reset surfaces saved selection clearing failures as local preference errors")
    func resetLocalPrivacyDataFailsWhenSelectionClearFails() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let pinnedItemsStore = makeIsolatedPinnedItemsStore()
        try pinnedItemsStore.togglePin(
            .openNews,
            accountAddress: "0x1111111111111111111111111111111111111111"
        )
        let service = PrivacyResetService(
            transactionalResetService: SwiftDataTransactionalPrivacyResetService(
                modelContainer: context.container
            ),
            ensCacheResetService: RecordingENSCacheResetService(),
            auraPlayPersistenceResetService: RecordingAuraPlayPersistenceResetService(),
            credentialResetService: RecordingCredentialPrivacyResetter(),
            selectionPersistence: FailingShellSelectionPersistence(),
            homePinnedItemsStore: pinnedItemsStore
        )

        await #expect {
            try await service.resetLocalPrivacyData()
        } throws: { error in
            guard case LocalDataResetError.phaseFailed(let phase, let completedPhases, _) = error else {
                return false
            }
            return phase == .localPreferences
                && completedPhases == [.transactionalStore, .supportCaches, .auraPlayPersistence, .credentialStore]
        }

        #expect(pinnedItemsStore.pinnedCount(for: "0x1111111111111111111111111111111111111111") == 1)
    }
}

private func makeIsolatedPinnedItemsStore() -> HomePinnedItemsStore {
    let suiteName = "PrivacyResetServiceTests.pins.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return HomePinnedItemsStore(userDefaults: defaults)
}

private func makeFixtureNFT(
    tokenId: String,
    accountAddress: String = "0x1111111111111111111111111111111111111111",
    contractAddress: String = "0x495f947276749ce646f68ac8c248420045cb7b5e"
) -> NFT {
    let network: Chain = .ethMainnet
    let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
    let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"

    return NFT(
        id: "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
        contract: NFT.Contract(address: contractAddress, chain: network),
        tokenId: tokenId,
        name: "Fixture \(tokenId)",
        image: nil,
        raw: nil,
        collection: NFT.Collection(
            name: "Fixture Collection",
            chain: network,
            contractAddress: contractAddress
        ),
        tokenUri: "ipfs://fixture-\(tokenId)",
        timeLastUpdated: "2025-01-01T00:00:00Z",
        network: network,
        accountAddress: accountAddress,
        contentType: "audio/mpeg",
        collectionName: "Fixture Collection",
        artistName: "Fixture Artist",
        animationUrl: "https://example.com/\(tokenId).mp3",
        audioUrl: "https://example.com/\(tokenId).mp3"
    )
}

private func makeFixtureMusicLibraryItem(
    id: String,
    sourceNFTID: String,
    accountAddressRawValue: String = "0x1111111111111111111111111111111111111111"
) -> MusicLibraryItem {
    MusicLibraryItem(
        id: id,
        sourceNFTID: sourceNFTID,
        accountAddressRawValue: accountAddressRawValue,
        networkRawValue: Chain.ethMainnet.rawValue,
        title: "Fixture Track",
        artistName: "Fixture Artist",
        collectionName: "Fixture Collection",
        normalizedTitleKey: "fixture track",
        normalizedArtistKey: "fixture artist",
        normalizedCollectionKey: "fixture collection",
        artworkURLString: "https://example.com/\(id).png",
        contentType: "audio/mpeg",
        playbackURLString: "https://example.com/\(id).mp3",
        availability: .ready,
        availabilityReason: nil,
        sourceUpdatedAtRawValue: nil
    )
}

private func makeFixtureStoredReceipt(
    accountAddress: String,
    chainRawValue: String = Chain.ethMainnet.rawValue
) throws -> StoredReceipt {
    try StoredReceipt(
        sequenceID: 1,
        createdAt: Date(timeIntervalSince1970: 123),
        actor: .system,
        mode: .observe,
        trigger: "fixture.trigger",
        scope: "fixture.scope",
        summary: "fixture.summary",
        provenance: "tests",
        isSuccess: true,
        timelineAccountAddress: accountAddress,
        timelineChainRawValue: chainRawValue,
        accountSequenceID: 1,
        payloadHash: "payload-hash-\(accountAddress)",
        previousReceiptHash: "previous-hash-\(accountAddress)",
        chainHash: "chain-hash-\(accountAddress)",
        details: ReceiptPayload(values: [:])
    )
}

private actor RecordingENSCacheResetService: ENSCacheResetting {
    private var resetCallCount = 0

    func resetCache() async {
        resetCallCount += 1
    }

    func resetCount() -> Int {
        resetCallCount
    }
}

private actor RecordingAuraPlayPersistenceResetService: AuraPlayPersistenceResetting {
    private var resetCallCount = 0

    func resetAuraPlayPersistence() async throws {
        resetCallCount += 1
    }

    func resetCount() -> Int {
        resetCallCount
    }
}

private actor FailingAuraPlayPersistenceResetService: AuraPlayPersistenceResetting {
    struct Failure: Error { }

    func resetAuraPlayPersistence() async throws {
        throw Failure()
    }
}

private actor FailingOnceAuraPlayPersistenceResetService: AuraPlayPersistenceResetting {
    struct Failure: Error { }

    private var didFail = false
    private var resetCallCount = 0

    func resetAuraPlayPersistence() async throws {
        resetCallCount += 1
        guard didFail else {
            didFail = true
            throw Failure()
        }
    }

    func attemptCount() -> Int {
        resetCallCount
    }
}

private actor RecordingCredentialPrivacyResetter: CredentialPrivacyResetting {
    private var count = 0

    func clearCredentials() async throws {
        count += 1
    }

    func clearCount() -> Int {
        count
    }
}

private actor FailingCredentialPrivacyResetter: CredentialPrivacyResetting {
    struct Failure: Error { }

    func clearCredentials() async throws {
        throw Failure()
    }
}

@MainActor
private final class RecordingShellSelectionPersistence: ShellSelectionPersisting {
    private(set) var clearSelectionCallCount = 0

    func loadSelection() async throws -> (address: String, chainID: String) {
        ("", Chain.ethMainnet.rawValue)
    }

    func saveSelection(address: String, chainID: String) async throws { }

    func clearSelection() async throws {
        clearSelectionCallCount += 1
    }
}

@MainActor
private final class FailingShellSelectionPersistence: ShellSelectionPersisting {
    struct Failure: Error { }

    func loadSelection() async throws -> (address: String, chainID: String) {
        ("", Chain.ethMainnet.rawValue)
    }

    func saveSelection(address: String, chainID: String) async throws { }

    func clearSelection() async throws {
        throw Failure()
    }
}
