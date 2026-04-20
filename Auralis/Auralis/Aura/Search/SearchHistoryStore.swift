import Foundation
import OSLog

struct SearchHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let accountAddress: String
    let normalizedQuery: String
    let query: String
    let recordedAt: Date

    var id: String {
        "\(accountAddress):\(normalizedQuery)"
    }
}

struct SearchHistoryStore {
    private static let logger = Logger(subsystem: "Auralis", category: "SearchHistoryStore")
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let maxEntriesPerAccount: Int

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "auralis.search.history.v1",
        maxEntriesPerAccount: Int = 12
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.maxEntriesPerAccount = maxEntriesPerAccount
    }

    func entries(for accountAddress: String?) -> [SearchHistoryEntry] {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        return loadEntries()
            .filter { $0.accountAddress == normalizedAccountAddress }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    func recordCommittedQuery(_ query: String, accountAddress: String?) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }

        let normalizedAccountAddress = normalizedAccount(accountAddress)
        let normalizedQuery = trimmedQuery.lowercased()
        var entries = loadEntries().filter {
            !($0.accountAddress == normalizedAccountAddress && $0.normalizedQuery == normalizedQuery)
        }

        entries.append(
            SearchHistoryEntry(
                accountAddress: normalizedAccountAddress,
                normalizedQuery: normalizedQuery,
                query: trimmedQuery,
                recordedAt: .now
            )
        )

        let grouped = Dictionary(grouping: entries, by: \.accountAddress)
        let trimmed = grouped.values.flatMap { accountEntries in
            accountEntries
                .sorted { $0.recordedAt > $1.recordedAt }
                .prefix(maxEntriesPerAccount)
        }
        saveEntries(Array(trimmed))
    }

    func removeEntry(id: String) {
        saveEntries(loadEntries().filter { $0.id != id })
    }

    func clear(accountAddress: String?) {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        saveEntries(loadEntries().filter { $0.accountAddress != normalizedAccountAddress })
    }

    func clearAll() {
        userDefaults.removeObject(forKey: storageKey)
    }

    private func normalizedAccount(_ address: String?) -> String {
        NFT.normalizedScopeComponent(address) ?? "global"
    }

    private func loadEntries() -> [SearchHistoryEntry] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([SearchHistoryEntry].self, from: data)
        } catch {
            Self.logger.error("Failed to decode search history for key \(self.storageKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func saveEntries(_ entries: [SearchHistoryEntry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            Self.logger.error("Failed to encode search history for key \(self.storageKey, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
    }
}
