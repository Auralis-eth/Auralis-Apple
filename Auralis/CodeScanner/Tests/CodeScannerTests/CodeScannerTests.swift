#if os(iOS)
@testable import CodeScanner
import AVFoundation
import SwiftUI
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

    @available(macCatalyst 14.0, *)
    @Test("scanner view preserves configured scan state without camera hardware")
    func scannerViewPreservesConfiguredScanState() {
        var didComplete = false
        let view = CodeScannerView(
            codeTypes: [.qr],
            scanMode: .continuousExcept(ignoredList: ["seen"]),
            manualSelect: true,
            scanInterval: 0.5,
            showViewfinder: true,
            requiresPhotoOutput: false,
            simulatedData: "auralis:test",
            shouldVibrateOnSuccess: false,
            isTorchOn: true,
            isPaused: true,
            isGalleryPresented: .constant(false),
            videoCaptureDevice: nil
        ) { _ in
            didComplete = true
        }

        #expect(view.codeTypes == [.qr])
        #expect(view.scanMode.isManual == false)
        #expect(view.manualSelect)
        #expect(view.scanInterval == 0.5)
        #expect(view.showViewfinder)
        #expect(view.requiresPhotoOutput == false)
        #expect(view.simulatedData == "auralis:test")
        #expect(view.shouldVibrateOnSuccess == false)
        #expect(view.isTorchOn)
        #expect(view.isPaused)
        #expect(didComplete == false)
    }
}
#endif
