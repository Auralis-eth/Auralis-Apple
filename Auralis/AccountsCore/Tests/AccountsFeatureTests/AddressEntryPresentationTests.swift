import AccountsFeature
import Testing

@MainActor
struct AddressEntryPresentationTests {
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

    @Test("pasteboard normalization trims whitespace and keeps non-empty wallet input")
    func pasteboardNormalizationKeepsTrimmedInput() throws {
        let value = AddressPasteboardValue(rawValue: "  0xb713338a3986312774cF274931802eD6Ea94bA93\n")

        #expect(try #require(value).address == "0xb713338a3986312774cF274931802eD6Ea94bA93")
    }

    @Test("pasteboard normalization rejects empty clipboard strings")
    func pasteboardNormalizationRejectsEmptyInput() {
        #expect(AddressPasteboardValue(rawValue: "   \n\t") == nil)
        #expect(AddressPasteboardValue(rawValue: nil) == nil)
    }
}
