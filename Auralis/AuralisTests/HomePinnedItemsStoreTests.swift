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
    func pinnedItemsStayScopedPerAccount() throws {
        let store = makeStore()
        let firstAccount = "0x1234567890abcdef1234567890abcdef12345678"
        let secondAccount = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"

        _ = try store.togglePin(.openSearch, accountAddress: firstAccount)
        _ = try store.togglePin(.openNews, accountAddress: secondAccount)

        #expect(store.pinnedActions(for: firstAccount) == [.openSearch])
        #expect(store.pinnedActions(for: secondAccount) == [.openNews])
        #expect(store.pinnedCount(for: firstAccount) == 1)
        #expect(store.pinnedCount(for: secondAccount) == 1)
    }

    @Test("home pinned-items store trims old pins beyond the configured limit")
    func pinnedItemsTrimToConfiguredLimit() throws {
        let store = makeStore()
        let account = "0x1234567890abcdef1234567890abcdef12345678"

        _ = try store.togglePin(.openSearch, accountAddress: account)
        _ = try store.togglePin(.openNews, accountAddress: account)
        _ = try store.togglePin(.openReceipts, accountAddress: account)
        _ = try store.togglePin(.openMusic, accountAddress: account)

        #expect(store.pinnedCount(for: account) == 3)
        #expect(store.isPinned(.openMusic, accountAddress: account))
        #expect(store.isPinned(.openReceipts, accountAddress: account))
        #expect(store.isPinned(.openNews, accountAddress: account))
    }

    @Test("mutating pinned items fails closed when stored data is corrupted")
    func corruptedPinnedItemsDoNotGetOverwrittenOnToggle() throws {
        let suiteName = "HomePinnedItemsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let storageKey = "auralis.tests.home-pinned-items"
        defaults.set(Data("not-json".utf8), forKey: storageKey)

        let store = HomePinnedItemsStore(
            userDefaults: defaults,
            storageKey: storageKey,
            maximumPinnedItemsPerAccount: 3
        )

        #expect(throws: HomePinnedItemsStoreError.corruptedStorage) {
            try store.togglePin(
                .openSearch,
                accountAddress: "0x1234567890abcdef1234567890abcdef12345678"
            )
        }
        #expect(defaults.data(forKey: storageKey) == Data("not-json".utf8))
    }
}
