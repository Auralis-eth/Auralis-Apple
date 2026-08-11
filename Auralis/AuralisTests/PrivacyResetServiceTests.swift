import ReceiptsCore
import ReceiptStorage
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
@testable import Auralis
import AccountStorage
import AccountsCore
import AuralisTestSupport
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
@Suite(.tags(.privacy, .swiftdata))
struct PrivacyResetServiceTests {
    @Test("resetLocalPrivacyData clears all scoped local state")
    func fullResetClearsAllScopedState() async throws {
        let fixture = try await arrangePopulatedFixture()

        try await fixture.performFullReset()

        #expect(fixture.searchHistoryStore.entries(for: nil).isEmpty)
        #expect(fixture.searchHistoryStore.entries(for: fixture.accountAddress).isEmpty)
        #expect(await fixture.ensCacheResetService.resetCount() == 1)
        #expect(await fixture.auraPlayPersistenceResetService.resetCount() == 1)
        #expect(await fixture.credentialResetService.clearCount() == 1)
        #expect(try fixture.context.fetch(FetchDescriptor<StoredReceipt>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<TokenHolding>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<NFT>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<MusicLibraryItem>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<AuralisPrimaryPersistence.Tag>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<NFT.Contract>()).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<NFT.Collection>()).isEmpty)
        #expect(fixture.selectionPersistence.clearSelectionCallCount == 1)
        #expect(fixture.pinnedItemsStore.pinnedActions(for: fixture.accountAddress).isEmpty)
    }

    @Test("privacy reset clears persisted ENS public identifier mappings")
    func resetLocalPrivacyDataClearsENSMappings() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "PrivacyResetServiceTests.ens-cache")
        defer { cleanup() }
        let storageKey = "ens-cache"
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let cacheStore = ENSResolutionCacheStore(
            userDefaultsStore: ENSCacheUserDefaults(defaults),
            storageKey: storageKey
        )
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
                fetchedAt: referenceDate
            )
        )
        await cacheStore.storeReverseResolution(
            ENSReverseCacheEntry(
                address: "0x1234567890abcdef1234567890abcdef12345678",
                ensName: "vitalik.eth",
                isForwardVerified: true,
                fetchedAt: referenceDate
            )
        )
        let payload = try #require(defaults.data(forKey: storageKey))
        let decodedPayload = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(decodedPayload.isEmpty == false)

        try await service.resetLocalPrivacyData()

        #expect(await cacheStore.cachedForwardResolution(forENS: "vitalik.eth") == nil)
        #expect(
            await cacheStore.cachedReverseResolution(
                forAddress: "0x1234567890abcdef1234567890abcdef12345678"
            ) == nil
        )
        #expect(defaults.data(forKey: storageKey) == nil)
    }

    private func arrangePopulatedFixture() async throws -> PrivacyResetFixture {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let ensCacheResetService = RecordingENSCacheResetService()
        let auraPlayPersistenceResetService = RecordingAuraPlayPersistenceResetService()
        let credentialResetService = RecordingCredentialPrivacyResetter()
        let selectionPersistence = RecordingShellSelectionPersistence()
        let pinnedItemsStore = makeIsolatedPinnedItemsStore()
        let service = PrivacyResetService(
            transactionalResetService: SwiftDataTransactionalPrivacyResetService(
                modelContainer: context.container
            ),
            ensCacheResetService: ensCacheResetService,
            auraPlayPersistenceResetService: auraPlayPersistenceResetService,
            credentialResetService: credentialResetService,
            selectionPersistence: selectionPersistence,
            homePinnedItemsStore: pinnedItemsStore
        )
        let searchHistoryStore = SearchHistoryStore(modelContext: context)
        let tokenHoldingsStore = SwiftDataTokenHoldingsStore(modelContext: context)
        let receiptStore = SwiftDataReceiptStore(
            modelContext: context,
            sequenceAllocator: ReceiptSequenceAllocator()
        )
        let referenceDate = Fixture.referenceDate
        let accountAddress = Fixture.Accounts.primary

        try await searchHistoryStore.recordCommittedQuery("Moonpunks", accountAddress: nil)
        try await searchHistoryStore.recordCommittedQuery("USDC", accountAddress: accountAddress)
        try await tokenHoldingsStore.upsertNativeHolding(
            accountAddress: accountAddress,
            chain: .ethMainnet,
            amountDisplay: "1.25",
            updatedAt: referenceDate
        )
        try pinnedItemsStore.togglePin(.openNews, accountAddress: accountAddress)
        context.insert(NFTFixture.music.with { $0.tokenId = "moon-1" }.build())
        context.insert(MusicLibraryItemFixture.music.with {
            $0.id = "track-1"
            $0.sourceNFTID = "music-source-1"
        }.build())
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

        return PrivacyResetFixture(
            context: context,
            service: service,
            searchHistoryStore: searchHistoryStore,
            ensCacheResetService: ensCacheResetService,
            auraPlayPersistenceResetService: auraPlayPersistenceResetService,
            credentialResetService: credentialResetService,
            selectionPersistence: selectionPersistence,
            pinnedItemsStore: pinnedItemsStore,
            accountAddress: accountAddress
        )
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

        context.insert(NFTFixture.music.with {
            $0.tokenId = "removed-1"
            $0.accountAddress = removed.address
        }.build())
        context.insert(MusicLibraryItemFixture.music.with {
            $0.id = "removed-track-1"
            $0.sourceNFTID = "removed-source-1"
            $0.accountAddress = removed.address
        }.build())
        removed.markAuraPlaySynced(on: .ethMainnet, at: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(try StoredReceiptFixture.successful.with { $0.accountAddress = removed.address }.build())
        try await SearchHistoryStore(modelContext: context).recordCommittedQuery("Removed Scope", accountAddress: removed.address)
        try await SwiftDataTokenHoldingsStore(modelContext: context).upsertNativeHolding(
            accountAddress: removed.address,
            chain: .ethMainnet,
            amountDisplay: "4.2",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        context.insert(NFTFixture.music.with {
            $0.tokenId = "preserved-1"
            $0.accountAddress = preserved.address
            $0.contractAddress = Fixture.contract("9999999999999999999999999999999999999999")
        }.build())
        context.insert(MusicLibraryItemFixture.music.with {
            $0.id = "preserved-track-1"
            $0.sourceNFTID = "preserved-source-1"
            $0.accountAddress = preserved.address
        }.build())
        preserved.markAuraPlaySynced(on: .ethMainnet, at: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(try StoredReceiptFixture.successful.with { $0.accountAddress = preserved.address }.build())
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
        #expect(remainingNFTs.contains(where: { $0.accountAddressRawValue == removed.address }) == false)
        #expect(remainingNFTs.contains(where: { $0.accountAddressRawValue == preserved.address }))
        #expect(remainingHoldings.contains(where: { $0.accountAddressRawValue == removed.address }) == false)
        #expect(remainingMusicItems.contains(where: { $0.accountAddressRawValue == removed.address }) == false)
        #expect(remainingMusicItems.contains(where: { $0.accountAddressRawValue == preserved.address }))
        #expect(remainingReceipts.contains(where: { $0.accountAddress == removed.address }))
        #expect(remainingReceipts.contains(where: { $0.accountAddress == preserved.address }))
        let remainingPreservedAccount = try #require(
            remainingAccounts.first { $0.address == preserved.address }
        )
        _ = try #require(remainingPreservedAccount.auraPlayLastSyncedAt(for: .ethMainnet))
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

        context.insert(NFTFixture.music.with {
            $0.tokenId = "stale-overwrite"
            $0.accountAddress = overwritten.address
        }.build())
        context.insert(MusicLibraryItemFixture.music.with {
            $0.id = "overwrite-track-1"
            $0.sourceNFTID = "overwrite-source-1"
            $0.accountAddress = overwritten.address
        }.build())
        overwritten.markAuraPlaySynced(on: .ethMainnet, at: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(try StoredReceiptFixture.successful.with { $0.accountAddress = overwritten.address }.build())
        try await SearchHistoryStore(modelContext: context).recordCommittedQuery("Overwrite Scope", accountAddress: overwritten.address)
        try await SwiftDataTokenHoldingsStore(modelContext: context).upsertNativeHolding(
            accountAddress: overwritten.address,
            chain: .ethMainnet,
            amountDisplay: "9.9",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        context.insert(NFTFixture.music.with {
            $0.tokenId = "keep-other"
            $0.accountAddress = other.address
            $0.contractAddress = Fixture.Contracts.alternate
        }.build())
        context.insert(MusicLibraryItemFixture.music.with {
            $0.id = "keep-other-track-1"
            $0.sourceNFTID = "keep-other-source-1"
            $0.accountAddress = other.address
        }.build())
        other.markAuraPlaySynced(on: .ethMainnet, at: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(try StoredReceiptFixture.successful.with { $0.accountAddress = other.address }.build())
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
        #expect(persistedNFTs.contains(where: { $0.accountAddressRawValue == overwritten.address }) == false)
        #expect(persistedNFTs.contains(where: { $0.accountAddressRawValue == other.address }))
        #expect(persistedHoldings.contains(where: { $0.accountAddressRawValue == overwritten.address }) == false)
        #expect(persistedMusicItems.contains(where: { $0.accountAddressRawValue == overwritten.address }) == false)
        #expect(persistedMusicItems.contains(where: { $0.accountAddressRawValue == other.address }))
        #expect(persistedReceipts.contains(where: { $0.accountAddress == overwritten.address }))
        #expect(persistedReceipts.contains(where: { $0.accountAddress == other.address }))
        #expect(persistedAccounts.contains(where: { $0.address == overwritten.address && $0.auraPlayLastSyncedAt(for: .ethMainnet) == nil }))
        let persistedOtherAccount = try #require(
            persistedAccounts.first { $0.address == other.address }
        )
        _ = try #require(persistedOtherAccount.auraPlayLastSyncedAt(for: .ethMainnet))
        #expect(SearchHistoryStore(modelContext: context).entries(for: overwritten.address).isEmpty)
        #expect(try context.fetch(FetchDescriptor<NFT.Contract>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NFT.Collection>()).count == 1)
    }

    @Test("logout cleanup clears active shell support data while preserving accounts when requested")
    func logoutCleanupClearsShellSupportData() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)

        let preservedAccount = EOAccount(
            address: Fixture.Accounts.primary,
            access: .readonly,
            name: "Preserved"
        )
        context.insert(preservedAccount)
        context.insert(NFTFixture.music.with {
            $0.tokenId = "logout-track"
            $0.accountAddress = preservedAccount.address
        }.build())
        context.insert(MusicLibraryItemFixture.music.with {
            $0.id = "logout-library-item"
            $0.sourceNFTID = "logout-source-1"
            $0.accountAddress = preservedAccount.address
        }.build())
        preservedAccount.markAuraPlaySynced(on: .ethMainnet, at: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(try StoredReceiptFixture.successful.with { $0.accountAddress = preservedAccount.address }.build())
        try await SearchHistoryStore(modelContext: context).recordCommittedQuery(
            "Logout Scope",
            accountAddress: preservedAccount.address
        )
        try await SwiftDataTokenHoldingsStore(modelContext: context).upsertNativeHolding(
            accountAddress: preservedAccount.address,
            chain: .ethMainnet,
            amountDisplay: "1.0",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
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
        let shmURL = URL(filePath: storeURL.path() + "-shm")
        let walURL = URL(filePath: storeURL.path() + "-wal")
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
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
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
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
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

    @Test("privacy reset invokes every reset boundary without hosted SwiftData fixture coupling")
    func resetLocalPrivacyDataInvokesEveryBoundary() async throws {
        let transactionalResetService = RecordingTransactionalPrivacyResetService()
        let ensCacheResetService = RecordingENSCacheResetService()
        let auraPlayPersistenceResetService = RecordingAuraPlayPersistenceResetService()
        let credentialResetService = RecordingCredentialPrivacyResetter()
        let selectionPersistence = RecordingShellSelectionPersistence()
        let pinnedItemsStore = makeIsolatedPinnedItemsStore()
        let accountAddress = "0x1111111111111111111111111111111111111111"
        try pinnedItemsStore.togglePin(.openNews, accountAddress: accountAddress)
        let service = PrivacyResetService(
            transactionalResetService: transactionalResetService,
            ensCacheResetService: ensCacheResetService,
            auraPlayPersistenceResetService: auraPlayPersistenceResetService,
            credentialResetService: credentialResetService,
            selectionPersistence: selectionPersistence,
            homePinnedItemsStore: pinnedItemsStore
        )

        try await service.resetLocalPrivacyData()

        #expect(await transactionalResetService.resetCount() == 1)
        #expect(await ensCacheResetService.resetCount() == 1)
        #expect(await auraPlayPersistenceResetService.resetCount() == 1)
        #expect(await credentialResetService.clearCount() == 1)
        #expect(selectionPersistence.clearSelectionCallCount == 1)
        #expect(pinnedItemsStore.pinnedActions(for: accountAddress).isEmpty)
    }

    @Test("disconnect all wallets removes every account before clearing local privacy data")
    func disconnectAllWalletsRemovesAccountsAndClearsPrivacyData() async throws {
        let accountStore = RecordingAccountStore(accounts: [
            EOAccount(address: "0x1111111111111111111111111111111111111111"),
            EOAccount(address: "0x2222222222222222222222222222222222222222"),
        ])
        let privacyResetService = RecordingPrivacyResetService()
        let service = AllWalletDisconnectService(
            accountStore: accountStore,
            privacyResetService: privacyResetService,
            activeAddressProvider: { "0x1111111111111111111111111111111111111111" }
        )

        try await service.disconnectAllWalletsAndEraseLocalData()

        #expect(try accountStore.listAccounts().isEmpty)
        #expect(accountStore.removedAddresses == [
            "0x1111111111111111111111111111111111111111",
            "0x2222222222222222222222222222222222222222",
        ])
        #expect(accountStore.activeAddresses == [
            "0x1111111111111111111111111111111111111111",
            "0x1111111111111111111111111111111111111111",
        ])
        #expect(privacyResetService.resetCallCount == 1)
    }
}

@MainActor
private struct PrivacyResetFixture {
    let context: ModelContext
    let service: PrivacyResetService
    let searchHistoryStore: SearchHistoryStore
    let ensCacheResetService: RecordingENSCacheResetService
    let auraPlayPersistenceResetService: RecordingAuraPlayPersistenceResetService
    let credentialResetService: RecordingCredentialPrivacyResetter
    let selectionPersistence: RecordingShellSelectionPersistence
    let pinnedItemsStore: HomePinnedItemsStore
    let accountAddress: String

    func performFullReset() async throws {
        try await service.resetLocalPrivacyData()
    }
}

private func makeIsolatedPinnedItemsStore() -> HomePinnedItemsStore {
    let suiteName = "PrivacyResetServiceTests.pins.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? UserDefaults()
    defaults.removePersistentDomain(forName: suiteName)
    return HomePinnedItemsStore(userDefaults: defaults)
}

@MainActor
private final class RecordingAccountStore: AccountStoring {
    private var accounts: [EOAccount]
    private(set) var removedAddresses: [String] = []
    private(set) var activeAddresses: [String?] = []

    init(accounts: [EOAccount]) {
        self.accounts = accounts
    }

    func listAccounts() throws -> [EOAccount] {
        accounts
    }

    func account(for rawAddress: String) throws -> EOAccount? {
        accounts.first { $0.address == rawAddress }
    }

    func createWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource,
        overwriteExisting: Bool,
        now: Date,
        correlationID: String?
    ) async throws -> EOAccount {
        EOAccount(address: rawAddress)
    }

    func activateWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource,
        selectedAt: Date,
        correlationID: String?
    ) async throws -> AccountActivationResult {
        AccountActivationResult(account: EOAccount(address: rawAddress), wasCreated: false)
    }

    func selectAccount(
        address rawAddress: String,
        selectedAt: Date,
        correlationID: String?
    ) async throws -> EOAccount {
        EOAccount(address: rawAddress)
    }

    func removeAccount(
        address rawAddress: String,
        activeAddress: String?,
        correlationID: String?
    ) async throws -> AccountRemovalResult {
        removedAddresses.append(rawAddress)
        activeAddresses.append(activeAddress)
        accounts.removeAll { $0.address == rawAddress }
        return AccountRemovalResult(removedAddress: rawAddress, fallbackAccount: accounts.first)
    }

    func persistCurrentChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount {
        EOAccount(address: rawAddress)
    }

    func persistPreferredChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount {
        EOAccount(address: rawAddress)
    }
}

@MainActor
private final class RecordingPrivacyResetService: PrivacyResetting {
    private(set) var resetCallCount = 0

    func resetLocalPrivacyData() async throws {
        resetCallCount += 1
    }
}

private actor RecordingTransactionalPrivacyResetService: TransactionalPrivacyResetting {
    private var resetCallCount = 0

    func resetTransactionalPrivacyData() async throws {
        resetCallCount += 1
    }

    func resetCount() -> Int {
        resetCallCount
    }
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
