@testable import Auralis
import AccountStorage
import AccountsCore
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ReceiptStorage
import SwiftData
import Testing

struct P0201FlowValidationTests {
    @Test("end-to-end flow covers add switch duplicate delete-active and relaunch persistence")
    @MainActor
    func validatesPrimaryWatchAccountFlow() async throws {
        let container = try TestModelContainers.inMemory(TestSchemas.primary)
        let context = ModelContext(container)
        let store = SwiftDataAccountStore(modelContext: context)
        let shellLogic = MainAuraShellLogic()

        let firstAccount = try await store.activateWatchAccount(
            from: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            source: .manualEntry,
            selectedAt: Date(timeIntervalSince1970: 100)
        )
        let secondAccount = try await store.activateWatchAccount(
            from: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            source: .guestPass,
            selectedAt: Date(timeIntervalSince1970: 200)
        )

        let duplicateSelection = try await store.activateWatchAccount(
            from: firstAccount.account.address.uppercased(),
            source: .qrScan,
            selectedAt: Date(timeIntervalSince1970: 300)
        )

        let deletion = try await store.removeAccount(
            address: duplicateSelection.account.address,
            activeAddress: duplicateSelection.account.address
        )
        let remainingAccounts = try store.listAccounts()

        let restore = shellLogic.restoreInitialState(
            currentAddress: deletion.fallbackAccount?.address ?? "",
            currentChainId: Chain.ethMainnet.rawValue,
            accounts: remainingAccounts
        )

        #expect(firstAccount.wasCreated)
        #expect(secondAccount.wasCreated)
        #expect(duplicateSelection.wasCreated == false)
        #expect(duplicateSelection.account.address == firstAccount.account.address)
        #expect(deletion.removedAddress == firstAccount.account.address)
        #expect(try #require(deletion.fallbackAccount).address == secondAccount.account.address)
        #expect(remainingAccounts.map(\.address) == [secondAccount.account.address])
        #expect(restore.currentAddress == secondAccount.account.address)
        #expect(try #require(restore.currentAccount).address == secondAccount.account.address)
    }

    @Test("logout preserves the roster and restore safely returns to onboarding without an active selection")
    @MainActor
    func validatesLogoutAndRelaunchBehavior() async throws {
        let container = try TestModelContainers.inMemory(TestSchemas.primary)
        let context = ModelContext(container)
        let store = SwiftDataAccountStore(modelContext: context)
        let shellLogic = MainAuraShellLogic()
        let homeLogic = HomeTabLogic()

        let account = try await store.activateWatchAccount(
            from: "0xcccccccccccccccccccccccccccccccccccccccc",
            source: .manualEntry,
            selectedAt: Date(timeIntervalSince1970: 100)
        )

        let persistedAccountsBeforeLogout = try store.listAccounts()
        let logoutPlan = homeLogic.logoutPlan()
        let restoreAfterLogout = shellLogic.restoreInitialState(
            currentAddress: logoutPlan.nextCurrentAddress,
            currentChainId: Chain.ethMainnet.rawValue,
            accounts: persistedAccountsBeforeLogout
        )

        #expect(persistedAccountsBeforeLogout.map(\.address) == [account.account.address])
        #expect(logoutPlan.shouldDeleteAccounts == false)
        #expect(restoreAfterLogout.currentAddress.isEmpty)
        #expect(restoreAfterLogout.currentAccount == nil)
    }
}
