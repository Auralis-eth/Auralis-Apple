import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct AccountStoreTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([EOAccount.self, NFT.self, Tag.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("create normalizes addresses and lists accounts by activity then recency added")
    @MainActor
    func createAndListAccounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = AccountStore(modelContext: context, eventRecorder: recorder)

        let older = try store.createWatchAccount(
            from: "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
            source: .manualEntry,
            now: Date(timeIntervalSince1970: 100)
        )
        let newer = try store.createWatchAccount(
            from: "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
            source: .guestPass,
            now: Date(timeIntervalSince1970: 200)
        )

        let accounts = try store.listAccounts()

        #expect(older.address == "0xabcdef1234567890abcdef1234567890abcdef12")
        #expect(newer.address == "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(accounts.map(\.address) == [newer.address, older.address])
        #expect(recorder.events == [
            .added(address: older.address),
            .added(address: newer.address)
        ])
    }

    @Test("select updates lastSelectedAt and moves the account to the front")
    @MainActor
    func selectAccount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = AccountStore(modelContext: context, eventRecorder: recorder)

        let first = try store.createWatchAccount(
            from: "0x1111111111111111111111111111111111111111",
            now: Date(timeIntervalSince1970: 100)
        )
        let second = try store.createWatchAccount(
            from: "0x2222222222222222222222222222222222222222",
            now: Date(timeIntervalSince1970: 200)
        )

        let selected = try store.selectAccount(
            address: first.address.uppercased(),
            selectedAt: Date(timeIntervalSince1970: 300)
        )
        let accounts = try store.listAccounts()

        #expect(selected.address == first.address)
        #expect(selected.lastSelectedAt == Date(timeIntervalSince1970: 300))
        #expect(accounts.map(\.address) == [first.address, second.address])
        #expect(recorder.events.last == .selected(address: first.address))
    }

    @Test("duplicate create is case-insensitive and requires explicit overwrite")
    @MainActor
    func duplicateCreateAndOverwrite() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = AccountStore(modelContext: context, eventRecorder: recorder)

        let original = try store.createWatchAccount(
            from: "0x3333333333333333333333333333333333333333",
            name: "Original",
            source: .manualEntry,
            now: Date(timeIntervalSince1970: 100)
        )

        do {
            _ = try store.createWatchAccount(
                from: "0x3333333333333333333333333333333333333333".uppercased(),
                name: "Replacement",
                source: .qrScan,
                now: Date(timeIntervalSince1970: 200)
            )
            Issue.record("Expected duplicateAddress error")
        } catch let error as AccountStoreError {
            #expect(error == .duplicateAddress(original.address))
        }

        let replaced = try store.createWatchAccount(
            from: original.address.uppercased(),
            name: "Replacement",
            source: .qrScan,
            overwriteExisting: true,
            now: Date(timeIntervalSince1970: 200)
        )

        let accounts = try store.listAccounts()

        #expect(accounts.count == 1)
        #expect(replaced !== original)
        #expect(replaced.address == original.address)
        #expect(replaced.name == "Replacement")
        #expect(replaced.source == .qrScan)
        #expect(replaced.addedAt == Date(timeIntervalSince1970: 200))
        #expect(recorder.events == [
            .added(address: original.address),
            .removed(address: original.address),
            .added(address: original.address)
        ])
    }

    @Test("remove returns the sorted fallback only when removing the active account")
    @MainActor
    func removeAccountAndFallback() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = AccountStore(modelContext: context, eventRecorder: recorder)

        let first = try store.createWatchAccount(
            from: "0x4444444444444444444444444444444444444444",
            now: Date(timeIntervalSince1970: 100)
        )
        let second = try store.createWatchAccount(
            from: "0x5555555555555555555555555555555555555555",
            now: Date(timeIntervalSince1970: 200)
        )
        _ = try store.selectAccount(
            address: first.address,
            selectedAt: Date(timeIntervalSince1970: 300)
        )

        let result = try store.removeAccount(
            address: first.address.uppercased(),
            activeAddress: first.address
        )

        let remaining = try store.listAccounts()

        #expect(result.removedAddress == first.address)
        #expect(result.fallbackAccount?.address == second.address)
        #expect(remaining.map(\.address) == [second.address])
        #expect(recorder.events.last == .removed(address: first.address))
    }
}

private final class RecordingAccountEventRecorder: AccountEventRecorder {
    private(set) var events: [AccountEvent] = []

    func record(_ event: AccountEvent) {
        events.append(event)
    }
}
