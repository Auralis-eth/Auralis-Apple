import AccountsCore
import AccountsFeature
import Foundation
import Testing

@Suite
struct AccountActivationErrorPresenterTests {
    private let presenter = AccountActivationErrorPresenter()

    @Test("activation error mapping keeps invalid wallet copy specific")
    func invalidAddressPresentsSpecificRecoveryCopy() {
        let presentation = presenter.presentation(for: AccountStoreError.invalidAddress)

        #expect(presentation.title == "Invalid Address")
        #expect(presentation.message == "The wallet address is invalid.")
    }

    @Test("activation error mapping treats duplicate accounts as a successful switch")
    func duplicateAddressPresentsExistingAccountCopy() {
        let presentation = presenter.presentation(
            for: AccountStoreError.duplicateAddress("0x1234567890abcdef1234567890abcdef12345678")
        )

        #expect(presentation.title == "Account Already Added")
        #expect(presentation.message == "Switched to the existing saved account for that address.")
    }

    @Test("activation error mapping falls back to deterministic save failure copy")
    func unknownErrorPresentsGenericSaveFailure() {
        let presentation = presenter.presentation(for: StubActivationError())

        #expect(presentation.title == "Save Failed")
        #expect(presentation.message == "Failed to save account: Storage temporarily unavailable.")
    }
}

private struct StubActivationError: LocalizedError {
    var errorDescription: String? {
        "Storage temporarily unavailable."
    }
}
