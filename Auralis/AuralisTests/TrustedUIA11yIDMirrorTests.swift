import AuraUI
import Testing
import AuralisMissionControl

/// `TrustedUIA11yID` documents that its values "are mirrored in AuraUI's central `A11yID` registry
/// so app UI tests and package-owned components share the same contract without coupling
/// AuralisMissionControl to AuraUI". That mirroring is maintained by hand across two packages that cannot see
/// each other, so nothing but this test stands between a renamed identifier and UI tests that
/// silently stop matching the control they name — a green suite that no longer checks anything.
///
/// The app target is the only place both modules are visible, which is why the contract is pinned
/// here rather than in either package.
struct TrustedUIA11yIDMirrorTests {
    @Test("every trusted-UI accessibility identifier matches AuraUI's mirror")
    func mirrorsMatch() {
        #expect(TrustedUIA11yID.approvalSurface == A11yID.TrustedUI.approvalSurface)
        #expect(TrustedUIA11yID.approvalApprove == A11yID.TrustedUI.approvalApprove)
        #expect(TrustedUIA11yID.approvalDeny == A11yID.TrustedUI.approvalDeny)
        #expect(TrustedUIA11yID.approvalDefer == A11yID.TrustedUI.approvalDefer)
        #expect(TrustedUIA11yID.approvalSubmitted == A11yID.TrustedUI.approvalSubmitted)
        #expect(TrustedUIA11yID.draftEditor == A11yID.TrustedUI.draftEditor)
        #expect(TrustedUIA11yID.draftSave == A11yID.TrustedUI.draftSave)
        #expect(TrustedUIA11yID.permissionCard == A11yID.TrustedUI.permissionCard)
        #expect(TrustedUIA11yID.receiptCard == A11yID.TrustedUI.receiptCard)
        #expect(TrustedUIA11yID.contextBundleCard == A11yID.TrustedUI.contextBundleCard)
        #expect(TrustedUIA11yID.unavailable == A11yID.TrustedUI.unavailable)
    }
}
