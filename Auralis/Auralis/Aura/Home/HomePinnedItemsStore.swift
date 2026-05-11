import AuralisPrimaryModels
import Foundation
import OSLog
import UserDefaultsAdapters

struct HomePinnedItemRecord: Codable, Equatable {
    let accountAddress: String
    let actionRawValue: String
    let pinnedAt: Date
}

enum HomePinnedItemsStoreError: LocalizedError, Equatable {
    case corruptedStorage

    var errorDescription: String? {
        switch self {
        case .corruptedStorage:
            return "Pinned actions could not be updated because local pinned-item data is corrupted."
        }
    }
}

struct HomePinnedItemsStore {
    private static let logger = Logger(subsystem: "Auralis", category: "HomePinnedItemsStore")
    private let store: UserDefaultsCodableStore<HomePinnedItemRecord>
    private let maximumPinnedItemsPerAccount: Int

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "auralis.home.pinned-items.v1",
        maximumPinnedItemsPerAccount: Int = 6
    ) {
        self.store = UserDefaultsCodableStore(
            userDefaults: userDefaults,
            key: storageKey,
            corruptionPolicy: .returnEmptyAndClear
        )
        self.maximumPinnedItemsPerAccount = maximumPinnedItemsPerAccount
    }

    func pinnedActions(for accountAddress: String?) -> Set<HomeLauncherAction> {
        Set(records(for: accountAddress).compactMap { HomeLauncherAction(rawValue: $0.actionRawValue) })
    }

    func pinnedCount(for accountAddress: String?) -> Int {
        pinnedActions(for: accountAddress).count
    }

    func isPinned(_ action: HomeLauncherAction, accountAddress: String?) -> Bool {
        pinnedActions(for: accountAddress).contains(action)
    }

    @discardableResult
    func togglePin(_ action: HomeLauncherAction, accountAddress: String?) throws -> Bool {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        let existingRecords = try loadRecordsForMutation()
        var records = existingRecords.filter {
            !($0.accountAddress == normalizedAccountAddress && $0.actionRawValue == action.rawValue)
        }

        let wasPinned = records.count != existingRecords.count
        if !wasPinned {
            records.append(
                HomePinnedItemRecord(
                    accountAddress: normalizedAccountAddress,
                    actionRawValue: action.rawValue,
                    pinnedAt: .now
                )
            )
        }

        let trimmed = Dictionary(grouping: records, by: \.accountAddress)
            .values
            .flatMap { accountRecords in
                accountRecords
                    .sorted { $0.pinnedAt > $1.pinnedAt }
                    .prefix(maximumPinnedItemsPerAccount)
            }

        try saveRecords(Array(trimmed))
        return !wasPinned
    }

    private func records(for accountAddress: String?) -> [HomePinnedItemRecord] {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        return loadRecords()
            .filter { $0.accountAddress == normalizedAccountAddress }
            .sorted { $0.pinnedAt > $1.pinnedAt }
    }

    private func normalizedAccount(_ address: String?) -> String {
        NFT.normalizedScopeComponent(address) ?? "global"
    }

    private func loadRecords() -> [HomePinnedItemRecord] {
        do {
            return try store.load()
        } catch {
            Self.logger.error("Failed to load pinned items: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func loadRecordsForMutation() throws -> [HomePinnedItemRecord] {
        do {
            return try store.load()
        } catch {
            Self.logger.error("Failed to load pinned items before mutation: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func saveRecords(_ records: [HomePinnedItemRecord]) throws {
        do {
            try store.save(records)
        } catch {
            Self.logger.error("Failed to save pinned items: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func clearAll() {
        store.clear()
    }
}
