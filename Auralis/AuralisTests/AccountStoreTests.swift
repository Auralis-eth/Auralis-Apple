@testable import Auralis
import AccountStorage
import AccountsCore
import Foundation
import SwiftData
import Testing

@MainActor
@Suite
struct AccountStoreTests {
    @Test("create normalizes addresses and lists accounts by activity then recency added")
    @MainActor
    func createAndListAccounts() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)

        let older = try await store.createWatchAccount(
            from: "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
            source: .manualEntry,
            now: Date(timeIntervalSince1970: 100)
        )
        let newer = try await store.createWatchAccount(
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

    @Test("account lookup uses canonical normalization for raw addresses")
    @MainActor
    func accountLookupNormalizesInput() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let store = SwiftDataAccountStore(modelContext: context)

        let account = try await store.createWatchAccount(
            from: "abcdefabcdefabcdefabcdefabcdefabcdefabcd",
            now: Date(timeIntervalSince1970: 100)
        )

        let lookedUpWithoutPrefix = try store.account(for: "ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD")
        let invalidLookup = try store.account(for: "not-an-address")

        #expect(try #require(lookedUpWithoutPrefix).address == account.address)
        #expect(invalidLookup == nil)
    }

    @Test("validation trims whitespace, normalizes case, and rejects ENS and embedded text")
    func validatesAddressInputDeterministically() {
        #expect(
            AccountStore.validateAddressInput("  0xABCDEF1234567890ABCDEF1234567890ABCDEF12  ")
                == .valid("0xabcdef1234567890abcdef1234567890abcdef12")
        )
        #expect(
            AccountStore.validateAddressInput("ABCDEF1234567890ABCDEF1234567890ABCDEF12")
                == .valid("0xabcdef1234567890abcdef1234567890abcdef12")
        )
        #expect(AccountStore.validateAddressInput("vitalik.eth") == .unsupportedENS)
        #expect(AccountStore.validateAddressInput("wallet: 0xabcdef1234567890abcdef1234567890abcdef12") == .invalidFormat)
        #expect(AccountStore.validateAddressInput("   ") == .empty)
    }

    @Test("phase 0 normalization contract uses lowercase canonical copyable addresses")
    func normalizationContractIsLowercaseCanonical() {
        let valid = AccountStore.validateAddressInput("ABCDEF1234567890ABCDEF1234567890ABCDEF12")
        let invalid = AccountStore.validateAddressInput("not-an-address")

        #expect(valid.normalizedAddress == "0xabcdef1234567890abcdef1234567890abcdef12")
        #expect(AccountStore.normalizeAddress("ABCDEF1234567890ABCDEF1234567890ABCDEF12") == "0xabcdef1234567890abcdef1234567890abcdef12")
        #expect(invalid.normalizedAddress == nil)
    }

    @Test("select updates lastSelectedAt and moves the account to the front")
    @MainActor
    func selectAccount() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)

        let first = try await store.createWatchAccount(
            from: "0x1111111111111111111111111111111111111111",
            now: Date(timeIntervalSince1970: 100)
        )
        let second = try await store.createWatchAccount(
            from: "0x2222222222222222222222222222222222222222",
            now: Date(timeIntervalSince1970: 200)
        )

        let selected = try await store.selectAccount(
            address: first.address.uppercased(),
            selectedAt: Date(timeIntervalSince1970: 300)
        )
        let accounts = try store.listAccounts()

        #expect(selected.address == first.address)
        #expect(selected.lastSelectedAt == Date(timeIntervalSince1970: 300))
        #expect(accounts.map(\.address) == [first.address, second.address])
        #expect(recorder.events.last == .selected(address: first.address))
    }

    @Test("activate creates a new account once and selects an existing duplicate deterministically")
    @MainActor
    func activateWatchAccountCreatesOrSelects() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)

        let created = try await store.activateWatchAccount(
            from: "0x1212121212121212121212121212121212121212",
            source: .manualEntry,
            selectedAt: Date(timeIntervalSince1970: 100)
        )
        let reused = try await store.activateWatchAccount(
            from: "0X1212121212121212121212121212121212121212",
            source: .qrScan,
            selectedAt: Date(timeIntervalSince1970: 200)
        )

        let accounts = try store.listAccounts()

        #expect(created.wasCreated)
        #expect(reused.wasCreated == false)
        #expect(created.account.address == reused.account.address)
        #expect(reused.account.lastSelectedAt == Date(timeIntervalSince1970: 200))
        #expect(accounts.count == 1)
        #expect(recorder.events == [
            .added(address: created.account.address),
            .selected(address: created.account.address),
            .selected(address: created.account.address)
        ])
    }

    @Test("duplicate create is case-insensitive and requires explicit overwrite")
    @MainActor
    func duplicateCreateAndOverwrite() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)

        let original = try await store.createWatchAccount(
            from: "0x3333333333333333333333333333333333333333",
            name: "Original",
            source: .manualEntry,
            now: Date(timeIntervalSince1970: 100)
        )

        do {
            _ = try await store.createWatchAccount(
                from: "0x3333333333333333333333333333333333333333".uppercased(),
                name: "Replacement",
                source: .qrScan,
                now: Date(timeIntervalSince1970: 200)
            )
            Issue.record("Expected duplicateAddress error")
        } catch let error as AccountStoreError {
            #expect(error == .duplicateAddress(original.address))
        }

        let replaced = try await store.createWatchAccount(
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

    @Test("invalid create and missing account operations fail with deterministic errors")
    @MainActor
    func invalidAndMissingAccountErrors() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let store = SwiftDataAccountStore(modelContext: context)

        await #expect(throws: AccountStoreError.invalidAddress) {
            _ = try await store.createWatchAccount(from: "definitely not an address")
        }

        await #expect(throws: AccountStoreError.accountNotFound("0x9999999999999999999999999999999999999999")) {
            _ = try await store.selectAccount(address: "0x9999999999999999999999999999999999999999")
        }

        await #expect(throws: AccountStoreError.accountNotFound("0x9999999999999999999999999999999999999999")) {
            _ = try await store.removeAccount(address: "0x9999999999999999999999999999999999999999")
        }
    }

    @Test("remove returns the sorted fallback only when removing the active account")
    @MainActor
    func removeAccountAndFallback() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)

        let first = try await store.createWatchAccount(
            from: "0x4444444444444444444444444444444444444444",
            now: Date(timeIntervalSince1970: 100)
        )
        let second = try await store.createWatchAccount(
            from: "0x5555555555555555555555555555555555555555",
            now: Date(timeIntervalSince1970: 200)
        )
        _ = try await store.selectAccount(
            address: first.address,
            selectedAt: Date(timeIntervalSince1970: 300)
        )

        let result = try await store.removeAccount(
            address: first.address.uppercased(),
            activeAddress: first.address
        )

        let remaining = try store.listAccounts()

        #expect(result.removedAddress == first.address)
        #expect(try #require(result.fallbackAccount).address == second.address)
        #expect(remaining.map(\.address) == [second.address])
        #expect(recorder.events.last == .removed(address: first.address))
    }

    @Test("remove does not compute a fallback when deleting an inactive account")
    @MainActor
    func removeInactiveAccountDoesNotFallback() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)

        let active = try await store.createWatchAccount(
            from: "0x6666666666666666666666666666666666666666",
            now: Date(timeIntervalSince1970: 100)
        )
        let inactive = try await store.createWatchAccount(
            from: "0x7777777777777777777777777777777777777777",
            now: Date(timeIntervalSince1970: 200)
        )
        _ = try await store.selectAccount(
            address: active.address,
            selectedAt: Date(timeIntervalSince1970: 300)
        )

        let result = try await store.removeAccount(
            address: inactive.address,
            activeAddress: active.address
        )

        let remaining = try store.listAccounts()

        #expect(result.removedAddress == inactive.address)
        #expect(result.fallbackAccount == nil)
        #expect(remaining.map(\.address) == [active.address])
        #expect(recorder.events.last == .removed(address: inactive.address))
    }

    @Test("activate reuses one caller-provided correlation ID across chained add and select events")
    @MainActor
    func activateWatchAccountPreservesCorrelationID() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let recorder = RecordingAccountEventRecorder()
        let store = SwiftDataAccountStore(modelContext: context, eventRecorder: recorder)
        let correlationID = "account-activation-123"

        _ = try await store.activateWatchAccount(
            from: "0xabababababababababababababababababababab",
            source: .manualEntry,
            selectedAt: Date(timeIntervalSince1970: 100),
            correlationID: correlationID
        )

        #expect(recorder.events == [
            .added(address: "0xabababababababababababababababababababab"),
            .selected(address: "0xabababababababababababababababababababab")
        ])
        #expect(recorder.recordedEvents.map(\.correlationID) == [correlationID, correlationID])
    }

    @Test("list orders by lastSelectedAt first and then newest added for ties")
    @MainActor
    func listAccountsUsesSelectionThenAddedAtOrdering() async throws {
        let container = try TestModelContainers.primary()
        let context = ModelContext(container)
        let store = SwiftDataAccountStore(modelContext: context)

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

        let accounts = try store.listAccounts()

        #expect(accounts.map(\.address) == [
            oldestSelected.address,
            newestUnselected.address,
            olderUnselected.address
        ])
    }

}

private final class RecordingAccountEventRecorder: AccountEventRecorder {
    struct RecordedEvent: Equatable {
        let event: AccountEvent
        let correlationID: String?
    }

    private(set) var recordedEvents: [RecordedEvent] = []

    var events: [AccountEvent] {
        recordedEvents.map(\.event)
    }

    func record(_ event: AccountEvent, correlationID: String?) async {
        recordedEvents.append(
            RecordedEvent(event: event, correlationID: correlationID)
        )
    }
}
