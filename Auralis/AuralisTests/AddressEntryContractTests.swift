@testable import Auralis
import Testing

@MainActor
@Suite
struct AddressEntryContractTests {
    @Test("address entry shows canonical copyable form for valid EVM input")
    func addressEntryShowsCanonicalForm() {
        let presentation = AddressEntryValidationPresentation.make(
            input: " ABCDEF1234567890ABCDEF1234567890ABCDEF12 "
        )

        #expect(presentation.validationMessage == nil)
        #expect(presentation.normalizedAddress == "0xabcdef1234567890abcdef1234567890abcdef12")
    }

    @Test("address entry keeps ENS input free of misleading inline address errors")
    func addressEntryHidesCanonicalFormForENSInput() {
        let presentation = AddressEntryValidationPresentation.make(input: "vitalik.eth")

        #expect(presentation.validationMessage == nil)
        #expect(presentation.normalizedAddress == nil)
    }

    @Test("address entry surfaces deterministic validation feedback for malformed wallet input")
    func addressEntryShowsInvalidAddressFeedback() {
        let presentation = AddressEntryValidationPresentation.make(input: "wallet: 0xabcdef")

        #expect(presentation.validationMessage == "Enter a valid EVM wallet address.")
        #expect(presentation.normalizedAddress == nil)
    }

    @Test("qr scan validation accepts canonical addresses and rejects ENS in the current slice")
    func qrScanValidationMatchesSupportedInputContract() {
        #expect(
            QRScanValidationOutcome.classify("0x1234567890abcdef1234567890abcdef12345678")
                == .valid
        )
        #expect(
            QRScanValidationOutcome.classify("vitalik.eth")
                == .alert(
                    title: "ENS Not Supported Yet",
                    message: "ENS names are not supported in this entry flow yet. Paste the resolved wallet address instead."
                )
        )
    }
}
