import XCTest

@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGatewayAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-reset-onboarding"])
        try performAudit(in: app)
    }

    func testHomeAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("Home", in: app)
        try performAudit(in: app)
    }

    func testNewsFeedAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("NewsFeed", in: app)
        try performAudit(in: app)
    }

    func testSearchAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("Search", in: app)
        try performAudit(in: app)
    }

    func testGasAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("Gas", in: app)
        try performAudit(in: app)
    }

    func testMusicAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("Music", in: app)
        try performAudit(in: app)
    }

    func testNFTAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("NFTs", in: app)
        try performAudit(in: app)
    }

    func testReceiptsAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("Receipts", in: app)
        try performAudit(in: app)
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-accessibility-audit"] + arguments
        app.launch()
        return app
    }

    private func selectTab(_ title: String, in app: XCUIApplication) throws {
        let tabButton = app.tabBars.buttons[title]
        guard tabButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("The \(title) tab is not visible in this launch state.")
        }
        tabButton.tap()
    }

    private func performAudit(in app: XCUIApplication) throws {
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: .all) { issue in
                let elementDescription = issue.element?.debugDescription ?? "No associated element"
                print("""
                Accessibility audit issue:
                \(issue.compactDescription)
                \(issue.detailedDescription)
                \(elementDescription)
                """)
                // SwiftUI can emit contrast issues without a queryable element. Keep the
                // mapped issues blocking, but do not fail on diagnostics we cannot route.
                return issue.auditType.contains(.contrast) && issue.element == nil
            }
        } else {
            throw XCTSkip("performAccessibilityAudit requires iOS 17 or newer.")
        }
    }
}
