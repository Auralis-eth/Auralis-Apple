import AccountsFeature
import Testing

@MainActor
struct AddressEntryContractTests {
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
