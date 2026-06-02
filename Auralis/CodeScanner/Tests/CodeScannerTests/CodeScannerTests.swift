#if os(iOS)
@testable import CodeScanner
import Testing

@Suite
struct CodeScannerTests {
    @Test("scan mode manual flag distinguishes manual capture from automatic modes")
    func scanModeManualFlagDistinguishesModes() {
        #expect(ScanMode.manual.isManual)
        #expect(ScanMode.once.isManual == false)
        #expect(ScanMode.oncePerCode.isManual == false)
        #expect(ScanMode.continuous.isManual == false)
        #expect(ScanMode.continuousExcept(ignoredList: ["seen"]).isManual == false)
    }
}
#endif
