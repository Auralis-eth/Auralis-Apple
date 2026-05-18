import ENS
import AuralisShellCore
import AuralisPrimaryModels
import Foundation
import MusicFeature
import ProviderKit
import ReceiptStorage
import SwiftData

protocol TransactionalPrivacyResetting: Sendable {
    func resetTransactionalPrivacyData() async throws
}

protocol AuraPlayPersistenceResetting: Sendable {
    func resetAuraPlayPersistence() async throws
}

protocol CredentialPrivacyResetting: Sendable {
    func clearCredentials() async throws
}

struct PasswordCredentialPrivacyResetter: CredentialPrivacyResetting {
    func clearCredentials() async throws {
        try await Password.clear()
    }
}

@ModelActor
actor SwiftDataTransactionalPrivacyResetService: TransactionalPrivacyResetting {
    func resetTransactionalPrivacyData() async throws {
        let receiptHeads = try latestReceiptHeads()
        let receiptIntegrityHeadStore = KeychainReceiptIntegrityHeadStore()

        try await receiptIntegrityHeadStore.clearAllHeads()
        do {
            try modelContext.performRollbackSafeMutation {
                try modelContext.delete(
                    model: StoredReceipt.self,
                    where: #Predicate<StoredReceipt> { _ in true }
                )
                try modelContext.delete(
                    model: SearchHistoryRecord.self,
                    where: #Predicate<SearchHistoryRecord> { _ in true }
                )
                try modelContext.delete(
                    model: TokenHolding.self,
                    where: #Predicate<TokenHolding> { _ in true }
                )
                try modelContext.delete(
                    model: MusicLibraryItem.self,
                    where: #Predicate<MusicLibraryItem> { _ in true }
                )
                try modelContext.delete(
                    model: Playlist.self,
                    where: #Predicate<Playlist> { _ in true }
                )
                try modelContext.deleteAllNFTData()

                let accounts = try modelContext.fetch(FetchDescriptor<EOAccount>())
                for account in accounts {
                    if account.trackedNFTCount != 0 {
                        account.trackedNFTCount = 0
                    }
                    account.clearAllAuraPlaySyncState()
                }
            }
        } catch {
            for (accountKey, chainHash) in receiptHeads {
                try? await receiptIntegrityHeadStore.saveHead(chainHash, for: accountKey)
            }
            throw error
        }
    }

    private func latestReceiptHeads() throws -> [String: String] {
        let receipts = try modelContext.fetch(FetchDescriptor<StoredReceipt>())
        var latestByAccount: [String: StoredReceipt] = [:]

        for receipt in receipts where receipt.hasCompleteIntegrityMetadata {
            let accountKey = receipt.receiptIntegrityAccountKey
            let current = latestByAccount[accountKey]
            if current == nil
                || receipt.accountSequenceID > current!.accountSequenceID
                || (
                    receipt.accountSequenceID == current!.accountSequenceID
                    && receipt.sequenceID > current!.sequenceID
                ) {
                latestByAccount[accountKey] = receipt
            }
        }

        return latestByAccount.mapValues(\.chainHash)
    }
}

private extension StoredReceipt {
    var hasCompleteIntegrityMetadata: Bool {
        !payloadHash.isEmpty
            && !previousReceiptHash.isEmpty
            && !chainHash.isEmpty
    }

    var receiptIntegrityAccountKey: String {
        guard let accountAddress, !accountAddress.isEmpty else {
            return "global"
        }
        return accountAddress.lowercased()
    }
}

actor AuraPlayStoreResetService: AuraPlayPersistenceResetting {
    private let fileManager: FileManager
    private let baseDirectory: URL?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func resetAuraPlayPersistence() throws {
        try AuraPlayModelContainer.resetStoreFiles(
            fileManager: fileManager,
            baseDirectory: baseDirectory
        )
    }
}

@ModelActor
actor SwiftDataAuraPlayPersistenceResetService: AuraPlayPersistenceResetting {
    func resetAuraPlayPersistence() throws {
        try modelContext.performRollbackSafeMutation {
            try modelContext.delete(
                model: AuraPlayMediaItem.self,
                where: #Predicate<AuraPlayMediaItem> { _ in true }
            )
        }
    }
}

@MainActor
protocol PrivacyResetting {
    func resetLocalPrivacyData() async throws
}

enum PrivacyResetPhase: String, Sendable, CaseIterable {
    case transactionalStore = "transactional wallet data"
    case supportCaches = "support caches"
    case auraPlayPersistence = "AuraPlay persistence"
    case credentialStore = "credential store"
    case localPreferences = "local preferences"
}

enum LocalDataResetError: LocalizedError {
    case rollbackCompleted(phase: PrivacyResetPhase, underlying: Error)
    case phaseFailed(
        phase: PrivacyResetPhase,
        completedPhases: [PrivacyResetPhase],
        underlying: Error
    )

    var errorDescription: String? {
        switch self {
        case .rollbackCompleted(let phase, _):
            return """
            Auralis could not clear \(phase.rawValue). Changes in that phase were rolled back, so you can retry the privacy reset safely.
            """
        case .phaseFailed(let phase, let completedPhases, _):
            let completedDescription = completedPhases.map(\.rawValue).joined(separator: ", ")
            return """
            Auralis already cleared \(completedDescription) before failing while clearing \(phase.rawValue). The reset is safe to retry and will continue from the remaining phases.
            """
        }
    }
}

@MainActor
struct PrivacyResetService: PrivacyResetting {
    private let transactionalResetService: any TransactionalPrivacyResetting
    private let ensCacheResetService: any ENSCacheResetting
    private let auraPlayPersistenceResetService: any AuraPlayPersistenceResetting
    private let credentialResetService: any CredentialPrivacyResetting
    private let selectionPersistence: any ShellSelectionPersisting
    private let homePinnedItemsStore: HomePinnedItemsStore

    init(
        transactionalResetService: any TransactionalPrivacyResetting,
        ensCacheResetService: any ENSCacheResetting,
        auraPlayPersistenceResetService: any AuraPlayPersistenceResetting,
        credentialResetService: any CredentialPrivacyResetting = PasswordCredentialPrivacyResetter(),
        selectionPersistence: any ShellSelectionPersisting = KeychainShellSelectionPersistence(),
        homePinnedItemsStore: HomePinnedItemsStore = HomePinnedItemsStore()
    ) {
        self.transactionalResetService = transactionalResetService
        self.ensCacheResetService = ensCacheResetService
        self.auraPlayPersistenceResetService = auraPlayPersistenceResetService
        self.credentialResetService = credentialResetService
        self.selectionPersistence = selectionPersistence
        self.homePinnedItemsStore = homePinnedItemsStore
    }

    func resetLocalPrivacyData() async throws {
        var completedPhases: [PrivacyResetPhase] = []

        do {
            try await transactionalResetService.resetTransactionalPrivacyData()
        } catch {
            throw LocalDataResetError.rollbackCompleted(
                phase: .transactionalStore,
                underlying: error
            )
        }
        completedPhases.append(.transactionalStore)

        await ensCacheResetService.resetCache()
        await GasPriceCache.shared.clearCache()
        completedPhases.append(.supportCaches)

        do {
            try await auraPlayPersistenceResetService.resetAuraPlayPersistence()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .auraPlayPersistence,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.auraPlayPersistence)

        do {
            try await credentialResetService.clearCredentials()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .credentialStore,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.credentialStore)

        do {
            try await selectionPersistence.clearSelection()
            homePinnedItemsStore.clearAll()
        } catch {
            throw LocalDataResetError.phaseFailed(
                phase: .localPreferences,
                completedPhases: completedPhases,
                underlying: error
            )
        }
        completedPhases.append(.localPreferences)
    }
}

@MainActor
enum PrivacyResetServices {
    static func live(
        modelContext: ModelContext,
        auraPlayModelContainer: ModelContainer?
    ) -> PrivacyResetService {
        PrivacyResetService(
            transactionalResetService: SwiftDataTransactionalPrivacyResetService(
                modelContainer: modelContext.container
            ),
            ensCacheResetService: ENSResolvers.cacheResetService(),
            auraPlayPersistenceResetService: auraPlayModelContainer.map {
                SwiftDataAuraPlayPersistenceResetService(modelContainer: $0)
            } ?? AuraPlayStoreResetService(),
            credentialResetService: PasswordCredentialPrivacyResetter(),
            selectionPersistence: KeychainShellSelectionPersistence(),
            homePinnedItemsStore: HomePinnedItemsStore()
        )
    }
}
