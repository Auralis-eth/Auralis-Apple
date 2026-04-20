@testable import Auralis
import Foundation
import SwiftData
import Testing

@MainActor
@Suite
struct SearchHistoryStoreTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SearchHistoryRecord.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeStore(maxEntriesPerAccount: Int = 12) throws -> SearchHistoryStore {
        let container = try makeContainer()
        let context = ModelContext(container)
        return SearchHistoryStore(
            modelContext: context,
            maxEntriesPerAccount: maxEntriesPerAccount
        )
    }

    @Test("records only committed queries per active account and de-duplicates repeats")
    func recordsCommittedQueriesPerAccount() throws {
        let store = try makeStore()

        store.recordCommittedQuery("Moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        store.recordCommittedQuery("moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        let firstAccountEntries = store.entries(for: "0x1111111111111111111111111111111111111111")
        let secondAccountEntries = store.entries(for: "0x2222222222222222222222222222222222222222")

        #expect(firstAccountEntries.count == 1)
        #expect(firstAccountEntries.first?.query == "moonpunks")
        #expect(secondAccountEntries.map(\.query) == ["USDC"])
    }

    @Test("same query in different accounts creates distinct scoped rows")
    func keepsScopesIndependentAcrossAccounts() throws {
        let store = try makeStore()

        store.recordCommittedQuery("Moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        store.recordCommittedQuery("Moonpunks", accountAddress: "0x2222222222222222222222222222222222222222")

        #expect(store.entries(for: "0x1111111111111111111111111111111111111111").count == 1)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").count == 1)
    }

    @Test("max entries per account trims older rows and keeps newest first")
    func trimsToMaximumEntriesPerAccount() throws {
        let store = try makeStore(maxEntriesPerAccount: 12)
        let account = "0x1111111111111111111111111111111111111111"

        for index in 0..<14 {
            store.recordCommittedQuery("query-\(index)", accountAddress: account)
        }

        let entries = store.entries(for: account)

        #expect(entries.count == 12)
        #expect(entries.first?.query == "query-13")
        #expect(entries.last?.query == "query-2")
    }

    @Test("clearing one account leaves other account history intact")
    func clearsOnlyScopedAccountHistory() throws {
        let store = try makeStore()

        store.recordCommittedQuery("Moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        store.clear(accountAddress: "0x1111111111111111111111111111111111111111")

        #expect(store.entries(for: "0x1111111111111111111111111111111111111111").isEmpty)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").map(\.query) == ["USDC"])
    }

    @Test("nil-account history persists separately and clear(nil) only removes that scope")
    func nilAccountHistoryUsesIndependentScope() throws {
        let store = try makeStore()

        store.recordCommittedQuery("Moonpunks", accountAddress: nil)
        store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        #expect(store.entries(for: nil).map(\.query) == ["Moonpunks"])
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").map(\.query) == ["USDC"])

        store.clear(accountAddress: nil)

        #expect(store.entries(for: nil).isEmpty)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").map(\.query) == ["USDC"])
    }

    @Test("clearAll removes every persisted search history row")
    func clearAllRemovesAllRows() throws {
        let store = try makeStore()

        store.recordCommittedQuery("Moonpunks", accountAddress: nil)
        store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        store.clearAll()

        #expect(store.entries(for: nil).isEmpty)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").isEmpty)
    }
}
