@testable import Auralis
import Foundation
import Testing

@Suite
struct HomePinnedItemsStoreTests {
    private func makeStore() -> HomePinnedItemsStore {
        let suiteName = "HomePinnedItemsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return HomePinnedItemsStore(
            userDefaults: defaults,
            storageKey: "auralis.tests.home-pinned-items",
            maximumPinnedItemsPerAccount: 3
        )
    }

    @Test("home pinned-items store keeps pins scoped per account")
    func pinnedItemsStayScopedPerAccount() {
        let store = makeStore()
        let firstAccount = "0x1234567890abcdef1234567890abcdef12345678"
        let secondAccount = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"

        _ = store.togglePin(.openSearch, accountAddress: firstAccount)
        _ = store.togglePin(.openNews, accountAddress: secondAccount)

        #expect(store.pinnedActions(for: firstAccount) == [.openSearch])
        #expect(store.pinnedActions(for: secondAccount) == [.openNews])
        #expect(store.pinnedCount(for: firstAccount) == 1)
        #expect(store.pinnedCount(for: secondAccount) == 1)
    }

    @Test("home pinned-items store trims old pins beyond the configured limit")
    func pinnedItemsTrimToConfiguredLimit() {
        let store = makeStore()
        let account = "0x1234567890abcdef1234567890abcdef12345678"

        _ = store.togglePin(.openSearch, accountAddress: account)
        _ = store.togglePin(.openNews, accountAddress: account)
        _ = store.togglePin(.openReceipts, accountAddress: account)
        _ = store.togglePin(.openMusic, accountAddress: account)

        #expect(store.pinnedCount(for: account) == 3)
        #expect(store.isPinned(.openMusic, accountAddress: account))
        #expect(store.isPinned(.openReceipts, accountAddress: account))
        #expect(store.isPinned(.openNews, accountAddress: account))
    }
}
