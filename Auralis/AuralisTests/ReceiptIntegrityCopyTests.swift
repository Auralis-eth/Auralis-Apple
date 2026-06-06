@testable import Auralis
import Testing

struct ReceiptIntegrityCopyTests {
    @Test("receipt integrity copy states local tamper evidence without overclaiming")
    func receiptIntegrityCopyStatesLocalGuarantee() {
        let copy = [
            ReceiptIntegrityCopy.timelineNotice,
            ReceiptIntegrityCopy.detailValue
        ].joined(separator: " ")

        #expect(copy.contains("local tamper evidence"))
        #expect(copy.contains("Keychain-protected head"))
        #expect(copy.contains("third-party proof"))
        #expect(copy.localizedCaseInsensitiveContains("non-repudiation") == false)
        #expect(copy.localizedCaseInsensitiveContains("audit-grade") == false)
    }
}
