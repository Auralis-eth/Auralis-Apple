import Foundation

struct HomePinnedItemRecord: Codable, Equatable {
    let accountAddress: String
    let actionRawValue: String
    let pinnedAt: Date
}

struct HomePinnedItemsStore {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let maximumPinnedItemsPerAccount: Int

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "auralis.home.pinned-items.v1",
        maximumPinnedItemsPerAccount: Int = 6
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
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
    func togglePin(_ action: HomeLauncherAction, accountAddress: String?) -> Bool {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        var records = loadRecords().filter { !($0.accountAddress == normalizedAccountAddress && $0.actionRawValue == action.rawValue) }

        let wasPinned = records.count != loadRecords().count
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

        saveRecords(Array(trimmed))
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
        guard let data = userDefaults.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([HomePinnedItemRecord].self, from: data) else {
            return []
        }

        return records
    }

    private func saveRecords(_ records: [HomePinnedItemRecord]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}
