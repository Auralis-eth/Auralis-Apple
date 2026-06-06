import AccountStorage
import AccountsCore
import AuralisPrimaryModels
import Foundation
import SwiftData
import Testing

@MainActor
struct SwiftDataAccountStoreTests {
    @Test("creating a watch account normalizes and persists the canonical address")
    func creatingWatchAccountNormalizesAndPersistsCanonicalAddress() async throws {
        let store = try makeStore()

        let account = try await store.createWatchAccount(
            from: "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
            source: .manualEntry,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(account.address == "0xabcdef1234567890abcdef1234567890abcdef12")
        #expect(try store.listAccounts().map(\.address) == [account.address])
    }

    @Test("fetching by canonical address matches case- and prefix-variant lookups while rejecting non-addresses")
    func fetchAccountByCanonicalAddress() async throws {
        let store = try makeStore()
        let account = try await store.createWatchAccount(
            from: "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
            now: Date(timeIntervalSince1970: 100)
        )

        let lookupWithPrefix = try store.account(for: "0XABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")
        let lookupWithoutPrefix = try store.account(for: "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")
        let invalidLookup = try store.account(for: "not-an-address")

        #expect(try #require(lookupWithPrefix).address == account.address)
        #expect(try #require(lookupWithoutPrefix).address == account.address)
        #expect(invalidLookup == nil)
    }

    @Test("overwriting an existing watch account replaces metadata without creating duplicate rows")
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

    @Test("overwriting an account removes stale account-scoped NFTs and tags")
    func overwritingAccountRemovesStaleScopedNFTsAndTags() async throws {
        let context = try makeContext()
        let store = makeStore(context: context)
        let address = "0x3333333333333333333333333333333333333333"
        let account = try await store.createWatchAccount(
            from: address,
            name: "Original",
            now: Date(timeIntervalSince1970: 100)
        )
        let tag = try Tag(name: "Archive")
        let nft = NFT(
            id: "stale-nft",
            contract: NFT.Contract(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            tokenId: "1",
            name: "Stale NFT",
            collection: nil,
            accountAddress: account.address,
            tags: [tag]
        )
        nft.assignOwnership(to: account)
        context.insert(tag)
        context.insert(nft)
        try context.save()

        _ = try await store.createWatchAccount(
            from: address.uppercased(),
            name: "Replacement",
            overwriteExisting: true,
            now: Date(timeIntervalSince1970: 200)
        )

        #expect(try store.listAccounts().map(\.name) == ["Replacement"])
        #expect(try context.fetch(FetchDescriptor<NFT>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Tag>()).isEmpty)
    }

    @Test("duplicate account inserts fail deterministically without changing the original row")
    func duplicateAccountInsertFailsWithoutChangingOriginalRow() async throws {
        let store = try makeStore()
        let address = "0x7777777777777777777777777777777777777777"
        let original = try await store.createWatchAccount(
            from: address,
            name: "Original",
            source: .manualEntry,
            now: Date(timeIntervalSince1970: 100)
        )

        await #expect(throws: AccountStoreError.duplicateAddress(original.address)) {
            _ = try await store.createWatchAccount(
                from: address.uppercased(),
                name: "Duplicate",
                source: .qrScan,
                overwriteExisting: false,
                now: Date(timeIntervalSince1970: 200)
            )
        }

        let accounts = try store.listAccounts()
        #expect(accounts.count == 1)
        let account = try #require(accounts.first)
        #expect(account.address == original.address)
        #expect(account.name == "Original")
        #expect(account.source == .manualEntry)
        #expect(account.addedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("removing the active account falls back to the newest remaining account")
    func removingActiveAccountFallsBackToNewestRemainingAccount() async throws {
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
        #expect(try #require(result.fallbackAccount).address == fallback.address)
        #expect(try store.listAccounts().map(\.address) == [fallback.address])
        #expect(try store.account(for: active.address) == nil)
    }

    @Test("listing accounts orders by selection, then newest added date, then address")
    func listingAccountsOrdersBySelectionNewestDateThenAddress() async throws {
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

    @Test("invalid addresses are rejected and unknown selections throw without creating account rows")
    func invalidAddressesAreRejectedWithoutCreatingAccountRows() async throws {
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
    try makeStore(context: makeContext())
}

@MainActor
private func makeStore(context: ModelContext) -> SwiftDataAccountStore {
    SwiftDataAccountStore(modelContext: context)
}

@MainActor
private func makeContext() throws -> ModelContext {
    try AccountStorageTestModelContainers.context()
}
