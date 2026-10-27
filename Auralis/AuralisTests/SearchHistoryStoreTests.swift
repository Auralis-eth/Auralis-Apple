@testable import Auralis
import AuralisCrypto
import Foundation
import SwiftData
import Testing

@MainActor
struct SearchHistoryStoreTests {
    private func makeStore(maxEntriesPerAccount: Int = 12) throws -> SearchHistoryStore {
        let container = try TestModelContainers.inMemory(TestSchemas.searchHistory)
        let context = ModelContext(container)
        return SearchHistoryStore(
            modelContext: context,
            maxEntriesPerAccount: maxEntriesPerAccount
        )
    }

    @Test("search history preserves its existing SwiftData entity name")
    func preservesSchemaEntityName() throws {
        let container = try TestModelContainers.inMemory(TestSchemas.searchHistory)

        #expect(container.schema.entity(for: SearchHistoryRecord.self)?.name == "SearchHistoryRecord")
    }

    @Test("account persistence participant restores every search history field")
    func accountParticipantRoundTripsAllFields() throws {
        let container = try TestModelContainers.inMemory(TestSchemas.searchHistory)
        let context = ModelContext(container)
        let recordedAt = Date(timeIntervalSince1970: 1_725_000_000)
        let account = "0x1111111111111111111111111111111111111111"
        context.insert(
            SearchHistoryRecord(
                accountAddressRawValue: account,
                normalizedQuery: "moonpunks",
                query: "MoonPunks",
                recordedAt: recordedAt
            )
        )
        try context.save()

        let snapshot = try SearchHistoryAccountPersistenceParticipant.capture(scope: account, in: context)
        try SearchHistoryAccountPersistenceParticipant.delete(scope: account, in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SearchHistoryRecord>()).isEmpty)

        try SearchHistoryAccountPersistenceParticipant.restore(snapshot, in: context)
        try context.save()

        let restored = try #require(context.fetch(FetchDescriptor<SearchHistoryRecord>()).first)
        #expect(restored.accountAddressRawValue == account)
        #expect(restored.normalizedQuery == "moonpunks")
        #expect(restored.query == "MoonPunks")
        #expect(restored.recordedAt == recordedAt)
        #expect(restored.id == "\(account):moonpunks")
    }

    @Test("account persistence participant only mutates its requested scope")
    func accountParticipantIsScoped() throws {
        let container = try TestModelContainers.inMemory(TestSchemas.searchHistory)
        let context = ModelContext(container)
        let firstAccount = "0x1111111111111111111111111111111111111111"
        let secondAccount = "0x2222222222222222222222222222222222222222"
        context.insert(SearchHistoryRecord(accountAddressRawValue: firstAccount, normalizedQuery: "first", query: "First"))
        context.insert(SearchHistoryRecord(accountAddressRawValue: secondAccount, normalizedQuery: "second", query: "Second"))
        try context.save()

        try SearchHistoryAccountPersistenceParticipant.delete(scope: firstAccount, in: context)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<SearchHistoryRecord>())
        #expect(remaining.map(\.accountAddressRawValue) == [secondAccount])
        #expect(remaining.map(\.query) == ["Second"])
    }

    @Test("records only committed queries per active account and de-duplicates repeats")
    func recordsCommittedQueriesPerAccount() async throws {
        let store = try makeStore()

        try await store.recordCommittedQuery("Moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        try await store.recordCommittedQuery("moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        try await store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        let firstAccountEntries = store.entries(for: "0x1111111111111111111111111111111111111111")
        let secondAccountEntries = store.entries(for: "0x2222222222222222222222222222222222222222")

        #expect(firstAccountEntries.count == 1)
        #expect(try #require(firstAccountEntries.first).query == "moonpunks")
        #expect(secondAccountEntries.map(\.query) == ["USDC"])
    }

    @Test("same query in different accounts creates distinct scoped rows")
    func keepsScopesIndependentAcrossAccounts() async throws {
        let store = try makeStore()

        try await store.recordCommittedQuery("Moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        try await store.recordCommittedQuery("Moonpunks", accountAddress: "0x2222222222222222222222222222222222222222")

        #expect(store.entries(for: "0x1111111111111111111111111111111111111111").count == 1)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").count == 1)
    }

    @Test("max entries per account trims older rows and keeps newest first")
    func trimsToMaximumEntriesPerAccount() async throws {
        let store = try makeStore(maxEntriesPerAccount: 12)
        let account = "0x1111111111111111111111111111111111111111"

        for index in 0..<14 {
            try await store.recordCommittedQuery("query-\(index)", accountAddress: account)
        }

        let entries = store.entries(for: account)

        #expect(entries.count == 12)
        #expect(try #require(entries.first).query == "query-13")
        #expect(try #require(entries.last).query == "query-2")
    }

    @Test("clearing one account leaves other account history intact")
    func clearsOnlyScopedAccountHistory() async throws {
        let store = try makeStore()

        try await store.recordCommittedQuery("Moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        try await store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        try await store.clear(accountAddress: "0x1111111111111111111111111111111111111111")

        #expect(store.entries(for: "0x1111111111111111111111111111111111111111").isEmpty)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").map(\.query) == ["USDC"])
    }

    @Test("nil-account history persists separately and clear(nil) only removes that scope")
    func nilAccountHistoryUsesIndependentScope() async throws {
        let store = try makeStore()

        try await store.recordCommittedQuery("Moonpunks", accountAddress: nil)
        try await store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        #expect(store.entries(for: nil).map(\.query) == ["Moonpunks"])
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").map(\.query) == ["USDC"])

        try await store.clear(accountAddress: nil)

        #expect(store.entries(for: nil).isEmpty)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").map(\.query) == ["USDC"])
    }

    @Test("clearAll removes every persisted search history row")
    func clearAllRemovesAllRows() async throws {
        let store = try makeStore()

        try await store.recordCommittedQuery("Moonpunks", accountAddress: nil)
        try await store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        try await store.clearAll()

        #expect(store.entries(for: nil).isEmpty)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").isEmpty)
    }
}
