@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
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
