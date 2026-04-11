import Testing
@testable import Auralis

@Suite
struct AuraPrimitiveContractTests {
    @Test("empty-state primitive preserves the configured shell feedback contract")
    func emptyStatePrimitiveStoresConfiguredContract() {
        let action = AuraFeedbackAction(title: "Retry", systemImage: "arrow.clockwise", handler: { })
        let view = AuraEmptyState(
            eyebrow: "Library",
            title: "Nothing Here Yet",
            message: "This is the shell empty state contract.",
            systemImage: "square.stack.3d.up",
            tone: .warning,
            primaryAction: action,
            secondaryAction: nil
        )

        #expect(view.eyebrow == "Library")
        #expect(view.title == "Nothing Here Yet")
        #expect(view.message == "This is the shell empty state contract.")
        #expect(view.systemImage == "square.stack.3d.up")
        #expect(view.tone == .warning)
        #expect(view.primaryAction?.title == "Retry")
        #expect(view.secondaryAction == nil)
    }

    @Test("error-banner primitive defaults to warning tone and optional action absence")
    func errorBannerPrimitiveUsesExpectedDefaults() {
        let banner = AuraErrorBanner(
            title: "Showing Last Sync",
            message: "Cached content remains visible.",
            systemImage: "exclamationmark.triangle"
        )

        #expect(banner.title == "Showing Last Sync")
        #expect(banner.message == "Cached content remains visible.")
        #expect(banner.systemImage == "exclamationmark.triangle")
        #expect(banner.tone == .warning)
        #expect(banner.action == nil)
    }
}
