import Foundation
import SwiftData
import SwiftDataAdapters

struct SearchHistorySnapshot: Sendable {
    private let accountAddressRawValue: String?
    private let normalizedQuery: String
    private let query: String
    private let recordedAt: Date

    init(_ record: SearchHistoryRecord) {
        self.accountAddressRawValue = record.accountAddressRawValue
        self.normalizedQuery = record.normalizedQuery
        self.query = record.query
        self.recordedAt = record.recordedAt
    }

    func model() -> SearchHistoryRecord {
        SearchHistoryRecord(
            accountAddressRawValue: accountAddressRawValue,
            normalizedQuery: normalizedQuery,
            query: query,
            recordedAt: recordedAt
        )
    }
}

enum SearchHistoryAccountPersistenceParticipant: ScopedPersistenceParticipant {
    static func capture(scope accountAddress: String, in context: ModelContext) throws -> [SearchHistorySnapshot] {
        try context.fetchSearchHistory(accountAddress: accountAddress).map(SearchHistorySnapshot.init)
    }

    static func delete(scope accountAddress: String, in context: ModelContext) throws {
        for record in try context.fetchSearchHistory(accountAddress: accountAddress) {
            context.delete(record)
        }
    }

    static func restore(_ snapshot: [SearchHistorySnapshot], in context: ModelContext) throws {
        guard context.container.schema.entity(for: SearchHistoryRecord.self) != nil else {
            return
        }
        snapshot.forEach { context.insert($0.model()) }
    }
}

private extension ModelContext {
    func fetchSearchHistory(accountAddress: String) throws -> [SearchHistoryRecord] {
        guard container.schema.entity(for: SearchHistoryRecord.self) != nil else {
            return []
        }

        let descriptor = FetchDescriptor<SearchHistoryRecord>(
            predicate: #Predicate<SearchHistoryRecord> { record in
                record.accountAddressRawValue == accountAddress
            }
        )
        return try fetch(descriptor)
    }
}
