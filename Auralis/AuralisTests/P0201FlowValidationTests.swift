import Foundation
import SwiftData
import Testing
@testable import Auralis

@Suite
struct P0201FlowValidationTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([EOAccount.self, NFT.self, Tag.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test("end-to-end flow covers add switch duplicate delete-active and relaunch persistence")
    @MainActor
    func validatesPrimaryWatchAccountFlow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AccountStore(modelContext: context)
        let shellLogic = MainAuraShellLogic()

        let firstAccount = try store.activateWatchAccount(
            from: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            source: .manualEntry,
            selectedAt: Date(timeIntervalSince1970: 100)
        )
        let secondAccount = try store.activateWatchAccount(
            from: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            source: .guestPass,
            selectedAt: Date(timeIntervalSince1970: 200)
        )

        let duplicateSelection = try store.activateWatchAccount(
            from: firstAccount.account.address.uppercased(),
            source: .qrScan,
            selectedAt: Date(timeIntervalSince1970: 300)
        )

        let deletion = try store.removeAccount(
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
        #expect(deletion.fallbackAccount?.address == secondAccount.account.address)
        #expect(remainingAccounts.map(\.address) == [secondAccount.account.address])
        #expect(restore.currentAddress == secondAccount.account.address)
        #expect(restore.currentAccount?.address == secondAccount.account.address)
    }

    @Test("logout preserves the roster and restore safely returns to onboarding without an active selection")
    @MainActor
    func validatesLogoutAndRelaunchBehavior() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let store = AccountStore(modelContext: context)
        let shellLogic = MainAuraShellLogic()
        let homeLogic = HomeTabLogic()

        let account = try store.activateWatchAccount(
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
