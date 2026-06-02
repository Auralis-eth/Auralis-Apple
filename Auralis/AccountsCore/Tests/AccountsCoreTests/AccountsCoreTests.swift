import AccountsCore
import Foundation
import Testing

@Suite
struct AccountsCoreTests {
    @Test("account input validation distinguishes empty, ENS, invalid, and valid input")
    func accountInputValidationClassifiesInputs() {
        #expect(AccountStore.validateAddressInput("   ") == .empty)
        #expect(AccountStore.validateAddressInput("vitalik.eth") == .unsupportedENS)
        #expect(AccountStore.validateAddressInput("0xnot-valid") == .invalidFormat)
        #expect(
            AccountStore.validateAddressInput(" 0xABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD ") ==
                .valid("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")
        )
    }

    @Test("account store errors expose stable user-facing descriptions")
    func accountStoreErrorsExposeDescriptions() {
        #expect(AccountStoreError.invalidAddress.errorDescription == "The wallet address is invalid.")
        #expect(
            AccountStoreError.duplicateAddress("0xabc").errorDescription ==
                "An account for 0xabc already exists."
        )
        #expect(
            AccountStoreError.accountNotFound("0xabc").errorDescription ==
                "No persisted account exists for 0xabc."
        )
    }
}
