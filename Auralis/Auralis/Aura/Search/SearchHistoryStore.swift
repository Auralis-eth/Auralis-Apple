import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import OSLog
import SwiftData

@ModelActor
private actor SearchHistoryPersistenceStore {
    func recordCommittedQuery(
        _ query: String,
        accountAddress: String?,
        maxEntriesPerAccount: Int,
        recordedAt: Date
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
            existingRecord.recordedAt = recordedAt
        } else {
            modelContext.insert(
                SearchHistoryRecord(
                    accountAddressRawValue: accountAddress,
                    normalizedQuery: normalizedQuery,
                    query: trimmedQuery,
                    recordedAt: recordedAt
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

        try modelContext.performRollbackSafeMutation {
            modelContext.delete(record)
        }
    }

    func clear(accountAddress: String?) throws {
        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            }
        )
        try modelContext.performRollbackSafeMutation {
            try modelContext.deleteFetchedModels(matching: descriptor)
        }
    }

    func clearAll() throws {
        try modelContext.performRollbackSafeMutation {
            try modelContext.deleteFetchedModels(matching: FetchDescriptor<SearchHistoryRecord>())
        }
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
    private let nowProvider: () -> Date

    init(
        modelContext: ModelContext,
        maxEntriesPerAccount: Int = 12,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.maxEntriesPerAccount = maxEntriesPerAccount
        self.persistenceStore = SearchHistoryPersistenceStore(modelContainer: modelContext.container)
        self.nowProvider = nowProvider
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
            maxEntriesPerAccount: maxEntriesPerAccount,
            recordedAt: nowProvider()
        )
    }

    func removeEntry(id: String) async throws {
        try await persistenceStore.removeEntry(id: id)
    }

    func clear(accountAddress: String?) async throws {
        try await persistenceStore.clear(accountAddress: normalizedAccount(accountAddress))
    }

    func clearAll() async throws {
        try await persistenceStore.clearAll()
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
