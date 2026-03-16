import Foundation
import Testing
@testable import Auralis

@Suite struct MainAuraShellLogicTests {
    private let logic = MainAuraShellLogic()

    @Test("initial restore falls back to Ethereum mainnet and no account when storage is empty")
    func restoreInitialStateWithNoAccount() {
        let result = logic.restoreInitialState(
            currentAddress: "",
            currentChainId: "not-a-chain",
            accounts: []
        )

        #expect(result.currentAddress.isEmpty)
        #expect(result.currentChain == .ethMainnet)
        #expect(result.currentAccount == nil)
        #expect(result.didFinishInitialStateRestore)
        #expect(result.shouldProcessPendingDeepLink)
    }

    @Test("initial restore reuses the persisted account when it is available")
    func restoreInitialStateUsesPersistedAccount() {
        let savedAccount = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly,
            name: "Saved"
        )

        let result = logic.restoreInitialState(
            currentAddress: savedAccount.address,
            currentChainId: Chain.baseMainnet.rawValue,
            accounts: [savedAccount]
        )

        #expect(result.currentAddress == savedAccount.address)
        #expect(result.currentChain == .baseMainnet)
        #expect(result.currentAccount?.address == savedAccount.address)
        #expect(result.currentAccount === savedAccount)
    }

    @Test("initial restore falls back to the preferred persisted account when the saved address is missing")
    func restoreInitialStateFallsBackToPersistedAccount() {
        let fallback = EOAccount(
            address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            access: .readonly,
            addedAt: Date(timeIntervalSince1970: 100),
            lastSelectedAt: Date(timeIntervalSince1970: 300)
        )
        let older = EOAccount(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            access: .readonly,
            addedAt: Date(timeIntervalSince1970: 200),
            lastSelectedAt: nil
        )

        let result = logic.restoreInitialState(
            currentAddress: "0x9999999999999999999999999999999999999999",
            currentChainId: Chain.ethMainnet.rawValue,
            accounts: [older, fallback]
        )

        #expect(result.currentAddress == fallback.address)
        #expect(result.currentChain == .ethMainnet)
        #expect(result.currentAccount === fallback)
    }

    @Test("initial restore clears a missing saved address when no persisted accounts remain")
    func restoreInitialStateClearsMissingSavedAddressWithoutAccounts() {
        let result = logic.restoreInitialState(
            currentAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            currentChainId: Chain.ethMainnet.rawValue,
            accounts: []
        )

        #expect(result.currentAddress.isEmpty)
        #expect(result.currentAccount == nil)
    }

    @Test("account change to a different address requests route reset and NFT refresh")
    func accountChangeTriggersRefreshForDifferentAddress() {
        let newAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        let result = logic.accountDidChange(
            newAccount: newAccount,
            persistedAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"
        )

        #expect(result.currentAddress == newAccount.address)
        #expect(result.shouldResetRoutes)
        #expect(result.shouldRefreshNFTs)
        #expect(result.shouldProcessPendingDeepLink)
    }

    @Test("account change to the same address does not trigger a redundant refresh")
    func accountChangeDoesNotRefreshForSameAddress() {
        let newAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        let result = logic.accountDidChange(
            newAccount: newAccount,
            persistedAddress: newAccount.address
        )

        #expect(result.currentAddress == newAccount.address)
        #expect(!result.shouldResetRoutes)
        #expect(!result.shouldRefreshNFTs)
        #expect(result.shouldProcessPendingDeepLink)
    }

    @Test("clearing the current account clears the persisted address without triggering a refresh")
    func accountChangeToNilClearsAddress() {
        let result = logic.accountDidChange(
            newAccount: nil,
            persistedAddress: "0x1234567890abcdef1234567890abcdef12345678"
        )

        #expect(result.currentAddress.isEmpty)
        #expect(!result.shouldResetRoutes)
        #expect(!result.shouldRefreshNFTs)
        #expect(result.shouldProcessPendingDeepLink)
    }

    @Test("address change resolves a persisted account and resets routes")
    func addressChangeUsesPersistedAccount() {
        let savedAccount = EOAccount(address: "0x1234567890abcdef1234567890abcdef12345678")

        let result = logic.addressDidChange(
            newAddress: savedAccount.address,
            accounts: [savedAccount]
        )

        #expect(result.currentAddress == savedAccount.address)
        #expect(result.currentAccount === savedAccount)
        #expect(result.shouldResetRoutes)
        #expect(result.shouldProcessPendingDeepLink)
    }

    @Test("address change keeps the requested address but only resolves persisted accounts")
    func addressChangeKeepsRequestedAddressWhenMissing() {
        let result = logic.addressDidChange(
            newAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            accounts: []
        )

        #expect(result.currentAddress == "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        #expect(result.currentAccount == nil)
        #expect(result.shouldResetRoutes)
        #expect(result.shouldProcessPendingDeepLink)
    }

    @Test("clearing the address clears the current account and still resets routes")
    func addressChangeToEmptyClearsAccount() {
        let result = logic.addressDidChange(
            newAddress: "",
            accounts: []
        )

        #expect(result.currentAddress.isEmpty)
        #expect(result.currentAccount == nil)
        #expect(result.shouldResetRoutes)
        #expect(result.shouldProcessPendingDeepLink)
    }
}
