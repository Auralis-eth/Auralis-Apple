@testable import Auralis
import Foundation
import Testing

@Suite
struct SearchHistoryStoreTests {
    @Test("records only committed queries per active account and de-duplicates repeats")
    func recordsCommittedQueriesPerAccount() {
        let userDefaults = UserDefaults(suiteName: "SearchHistoryStoreTests.recordsCommittedQueriesPerAccount")!
        userDefaults.removePersistentDomain(forName: "SearchHistoryStoreTests.recordsCommittedQueriesPerAccount")
        let store = SearchHistoryStore(userDefaults: userDefaults, storageKey: "history")

        store.recordCommittedQuery("Moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        store.recordCommittedQuery("moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        let firstAccountEntries = store.entries(for: "0x1111111111111111111111111111111111111111")
        let secondAccountEntries = store.entries(for: "0x2222222222222222222222222222222222222222")

        #expect(firstAccountEntries.count == 1)
        #expect(firstAccountEntries.first?.query == "moonpunks")
        #expect(secondAccountEntries.map(\.query) == ["USDC"])
    }

    @Test("clearing one account leaves other account history intact")
    func clearsOnlyScopedAccountHistory() {
        let userDefaults = UserDefaults(suiteName: "SearchHistoryStoreTests.clearsOnlyScopedAccountHistory")!
        userDefaults.removePersistentDomain(forName: "SearchHistoryStoreTests.clearsOnlyScopedAccountHistory")
        let store = SearchHistoryStore(userDefaults: userDefaults, storageKey: "history")

        store.recordCommittedQuery("Moonpunks", accountAddress: "0x1111111111111111111111111111111111111111")
        store.recordCommittedQuery("USDC", accountAddress: "0x2222222222222222222222222222222222222222")

        store.clear(accountAddress: "0x1111111111111111111111111111111111111111")

        #expect(store.entries(for: "0x1111111111111111111111111111111111111111").isEmpty)
        #expect(store.entries(for: "0x2222222222222222222222222222222222222222").map(\.query) == ["USDC"])
    }
}
