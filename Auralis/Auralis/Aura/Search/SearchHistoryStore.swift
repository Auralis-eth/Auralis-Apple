import Foundation
import OSLog
import SwiftData

struct SearchHistoryEntry: Equatable, Identifiable, Sendable {
    let accountAddress: String?
    let normalizedQuery: String
    let query: String
    let recordedAt: Date

    init(
        accountAddress: String?,
        normalizedQuery: String,
        query: String,
        recordedAt: Date
    ) {
        self.accountAddress = accountAddress
        self.normalizedQuery = normalizedQuery
        self.query = query
        self.recordedAt = recordedAt
    }

    init(record: SearchHistoryRecord) {
        self.accountAddress = record.accountAddressRawValue
        self.normalizedQuery = record.normalizedQuery
        self.query = record.query
        self.recordedAt = record.recordedAt
    }

    var id: String {
        SearchHistoryRecord.scopedID(
            accountAddressRawValue: accountAddress,
            normalizedQuery: normalizedQuery
        )
    }
}

@MainActor
struct SearchHistoryStore {
    private static let logger = Logger(subsystem: "Auralis", category: "SearchHistoryStore")
    private let modelContext: ModelContext
    private let maxEntriesPerAccount: Int

    init(
        modelContext: ModelContext,
        maxEntriesPerAccount: Int = 12
    ) {
        self.modelContext = modelContext
        self.maxEntriesPerAccount = maxEntriesPerAccount
    }

    func entries(for accountAddress: String?) -> [SearchHistoryEntry] {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        return fetchRecords()
            .filter { $0.accountAddressRawValue == normalizedAccountAddress }
            .sorted { $0.recordedAt > $1.recordedAt }
            .map(SearchHistoryEntry.init(record:))
    }

    func recordCommittedQuery(_ query: String, accountAddress: String?) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }

        let normalizedAccountAddress = normalizedAccount(accountAddress)
        let normalizedQuery = trimmedQuery.lowercased()

        if let existingRecord = fetchRecords().first(where: {
            $0.accountAddressRawValue == normalizedAccountAddress && $0.normalizedQuery == normalizedQuery
        }) {
            existingRecord.query = trimmedQuery
            existingRecord.recordedAt = .now
        } else {
            modelContext.insert(
                SearchHistoryRecord(
                    accountAddressRawValue: normalizedAccountAddress,
                    normalizedQuery: normalizedQuery,
                    query: trimmedQuery,
                    recordedAt: .now
                )
            )
        }

        trimExcessEntries(for: normalizedAccountAddress)
        saveContext()
    }

    func removeEntry(id: String) {
        guard let record = fetchRecords().first(where: { $0.id == id }) else {
            return
        }

        modelContext.delete(record)
        saveContext()
    }

    func clear(accountAddress: String?) {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        fetchRecords()
            .filter { $0.accountAddressRawValue == normalizedAccountAddress }
            .forEach(modelContext.delete)
        saveContext()
    }

    func clearAll() {
        fetchRecords().forEach(modelContext.delete)
        saveContext()
    }

    private func normalizedAccount(_ address: String?) -> String? {
        NFT.normalizedScopeComponent(address)
    }

    private func fetchRecords() -> [SearchHistoryRecord] {
        do {
            return try modelContext.fetch(FetchDescriptor<SearchHistoryRecord>())
        } catch {
            Self.logger.error("Failed to fetch search history records: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func trimExcessEntries(for accountAddress: String?) {
        let overflowRecords = fetchRecords()
            .filter { $0.accountAddressRawValue == accountAddress }
            .sorted { $0.recordedAt > $1.recordedAt }
            .dropFirst(maxEntriesPerAccount)

        overflowRecords.forEach(modelContext.delete)
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save search history records: \(error.localizedDescription, privacy: .public)")
        }
    }
}
