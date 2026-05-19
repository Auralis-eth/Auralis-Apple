import AccountStorage
import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ReceiptStorage
import SwiftData
import Testing
import TokenStorage

@MainActor
@Suite
struct SwiftDataAccountStoreTests {
    @Test("save new account")
    func saveNewAccount() async throws {
        let store = try makeStore()

        let account = try await store.createWatchAccount(
            from: "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
            source: .manualEntry,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(account.address == "0xabcdef1234567890abcdef1234567890abcdef12")
        #expect(try store.listAccounts().map(\.address) == [account.address])
    }

    @Test("fetch account by canonical address")
    func fetchAccountByCanonicalAddress() async throws {
        let store = try makeStore()
        let account = try await store.createWatchAccount(
            from: "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
            now: Date(timeIntervalSince1970: 100)
        )

        let lookupWithPrefix = try store.account(for: "0XABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")
        let lookupWithoutPrefix = try store.account(for: "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")
        let invalidLookup = try store.account(for: "not-an-address")

        #expect(lookupWithPrefix?.address == account.address)
        #expect(lookupWithoutPrefix?.address == account.address)
        #expect(invalidLookup == nil)
    }

    @Test("update existing account without duplicate rows")
    func updateExistingAccountWithoutDuplicateRows() async throws {
        let store = try makeStore()
        let original = try await store.createWatchAccount(
            from: "0x3333333333333333333333333333333333333333",
            name: "Original",
            source: .manualEntry,
            now: Date(timeIntervalSince1970: 100)
        )

        let replaced = try await store.createWatchAccount(
            from: original.address.uppercased(),
            name: "Replacement",
            source: .qrScan,
            overwriteExisting: true,
            now: Date(timeIntervalSince1970: 200)
        )
        let accounts = try store.listAccounts()

        #expect(accounts.count == 1)
        #expect(replaced.address == original.address)
        #expect(replaced.name == "Replacement")
        #expect(replaced.source == .qrScan)
        #expect(replaced.addedAt == Date(timeIntervalSince1970: 200))
    }

    @Test("delete account")
    func deleteAccount() async throws {
        let store = try makeStore()
        let active = try await store.createWatchAccount(
            from: "0x4444444444444444444444444444444444444444",
            now: Date(timeIntervalSince1970: 100)
        )
        let fallback = try await store.createWatchAccount(
            from: "0x5555555555555555555555555555555555555555",
            now: Date(timeIntervalSince1970: 200)
        )

        let result = try await store.removeAccount(
            address: active.address.uppercased(),
            activeAddress: active.address
        )

        #expect(result.removedAddress == active.address)
        #expect(result.fallbackAccount?.address == fallback.address)
        #expect(try store.listAccounts().map(\.address) == [fallback.address])
        #expect(try store.account(for: active.address) == nil)
    }

    @Test("account list orders by selection, added date, then address")
    func accountListOrdering() async throws {
        let store = try makeStore()
        let oldestSelected = try await store.createWatchAccount(
            from: "0x8888888888888888888888888888888888888888",
            now: Date(timeIntervalSince1970: 100)
        )
        let newestUnselected = try await store.createWatchAccount(
            from: "0x9999999999999999999999999999999999999999",
            now: Date(timeIntervalSince1970: 300)
        )
        let olderUnselected = try await store.createWatchAccount(
            from: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            now: Date(timeIntervalSince1970: 200)
        )

        _ = try await store.selectAccount(
            address: oldestSelected.address,
            selectedAt: Date(timeIntervalSince1970: 400)
        )

        #expect(try store.listAccounts().map(\.address) == [
            oldestSelected.address,
            newestUnselected.address,
            olderUnselected.address
        ])
    }

    @Test("invalid and corrupt address handling")
    func invalidAndCorruptAddressHandling() async throws {
        let store = try makeStore()

        await #expect(throws: AccountStoreError.invalidAddress) {
            _ = try await store.createWatchAccount(from: "definitely not an address")
        }

        await #expect(throws: AccountStoreError.accountNotFound("0x9999999999999999999999999999999999999999")) {
            _ = try await store.selectAccount(address: "0x9999999999999999999999999999999999999999")
        }

        #expect(try store.account(for: "not-an-address") == nil)
    }
}

@MainActor
private func makeStore() throws -> SwiftDataAccountStore {
    let container = try ModelContainer(
        for: Schema([
            EOAccount.self,
            NFT.self,
            Tag.self,
            StoredReceipt.self,
            Playlist.self,
            MusicLibraryItem.self,
            TokenHolding.self,
            SearchHistoryRecord.self,
        ]),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    return SwiftDataAccountStore(modelContext: ModelContext(container))
}
