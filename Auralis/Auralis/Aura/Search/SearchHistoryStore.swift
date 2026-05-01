import Foundation
import OSLog
import SwiftData

@ModelActor
private actor SearchHistoryPersistenceStore {
    func recordCommittedQuery(
        _ query: String,
        accountAddress: String?,
        maxEntriesPerAccount: Int
    ) throws {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }

        let normalizedQuery = trimmedQuery.lowercased()

        if let existingRecord = try fetchRecord(
            accountAddress: accountAddress,
            normalizedQuery: normalizedQuery
        ) {
            existingRecord.query = trimmedQuery
            existingRecord.recordedAt = .now
        } else {
            modelContext.insert(
                SearchHistoryRecord(
                    accountAddressRawValue: accountAddress,
                    normalizedQuery: normalizedQuery,
                    query: trimmedQuery,
                    recordedAt: .now
                )
            )
        }

        try trimExcessEntries(for: accountAddress, maxEntriesPerAccount: maxEntriesPerAccount)
        try modelContext.save()
    }

    func removeEntry(id: String) throws {
        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.id == id
            }
        )
        guard let record = try modelContext.fetch(descriptor).first else {
            return
        }

        modelContext.delete(record)
        try modelContext.save()
    }

    func clear(accountAddress: String?) throws {
        try modelContext.delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            }
        )
        try modelContext.save()
    }

    func clearAll() throws {
        try modelContext.delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { _ in true }
        )
        try modelContext.save()
    }

    private func fetchRecord(
        accountAddress: String?,
        normalizedQuery: String
    ) throws -> SearchHistoryRecord? {
        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress &&
                record.normalizedQuery == normalizedQuery
            }
        )

        return try modelContext.fetch(descriptor).first
    }

    private func fetchScopedRecords(accountAddress: String?) throws -> [SearchHistoryRecord] {
        try modelContext.fetch(scopedRecordsDescriptor(accountAddress: accountAddress))
    }

    private func scopedRecordsDescriptor(accountAddress: String?) -> FetchDescriptor<SearchHistoryRecord> {
        FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            },
            sortBy: [SortDescriptor(\SearchHistoryRecord.recordedAt, order: .reverse)]
        )
    }

    private func trimExcessEntries(
        for accountAddress: String?,
        maxEntriesPerAccount: Int
    ) throws {
        let overflowRecords = try fetchScopedRecords(accountAddress: accountAddress)
            .dropFirst(maxEntriesPerAccount)

        overflowRecords.forEach(modelContext.delete)
    }
}

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
    private let persistenceStore: SearchHistoryPersistenceStore

    init(
        modelContext: ModelContext,
        maxEntriesPerAccount: Int = 12
    ) {
        self.modelContext = modelContext
        self.maxEntriesPerAccount = maxEntriesPerAccount
        self.persistenceStore = SearchHistoryPersistenceStore(modelContainer: modelContext.container)
    }

    func entries(for accountAddress: String?) -> [SearchHistoryEntry] {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        do {
            return try fetchRecords(accountAddress: normalizedAccountAddress)
                .map(SearchHistoryEntry.init(record:))
        } catch {
            Self.logger.error("Failed to load search history entries: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func recordCommittedQuery(_ query: String, accountAddress: String?) async throws {
        try await persistenceStore.recordCommittedQuery(
            query,
            accountAddress: normalizedAccount(accountAddress),
            maxEntriesPerAccount: maxEntriesPerAccount
        )
    }

    func removeEntry(id: String) async throws {
        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.id == id
            }
        )
        guard let record = try modelContext.fetch(descriptor).first else {
            return
        }

        modelContext.delete(record)
        try modelContext.save()
    }

    func clear(accountAddress: String?) async throws {
        let normalizedAccountAddress = normalizedAccount(accountAddress)
        try modelContext.delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == normalizedAccountAddress
            }
        )
        try modelContext.save()
    }

    func clearAll() async throws {
        try modelContext.delete(
            model: SearchHistoryRecord.self,
            where: #Predicate<SearchHistoryRecord> { _ in true }
        )
        try modelContext.save()
    }

    private func normalizedAccount(_ address: String?) -> String? {
        NFT.normalizedScopeComponent(address)
    }

    private func fetchRecords(accountAddress: String?) throws -> [SearchHistoryRecord] {
        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            },
            sortBy: [SortDescriptor(\SearchHistoryRecord.recordedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
