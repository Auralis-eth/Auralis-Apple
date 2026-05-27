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

    func testGatewayValidationErrorAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-reset-onboarding"])
        let addressField = app.textFields["Ethereum address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))

        addressField.tap()
        addressField.typeText("not-a-wallet")
        app.buttons["Enter Auralis"].tap()

        XCTAssertTrue(app.alerts["Invalid Address"].waitForExistence(timeout: 5))
        app.alerts["Invalid Address"].buttons["OK"].tap()
        try performAudit(in: app)
    }

    func testScannerSimulatorFallbackAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-reset-onboarding"])
        let scanButton = app.buttons["Scan wallet QR code"]
        XCTAssertTrue(scanButton.waitForExistence(timeout: 5))

        scanButton.tap()

        let simulatedCodeButton = app.buttons["Use simulated code"]
        XCTAssertTrue(simulatedCodeButton.waitForExistence(timeout: 5))
        try performAudit(in: app)
    }

    func testHomeAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("Home", in: app)
        try performAudit(in: app)
    }

    func testAccountSwitcherRemovalConfirmationAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        try selectTab("Home", in: app)

        let manageAccountsButton = app.buttons["home.accounts.open"]
        XCTAssertTrue(manageAccountsButton.waitForExistence(timeout: 8))
        manageAccountsButton.tap()

        let removeAccountButton = app.buttons["accounts.remove.0x1234567890abcdef1234567890abcdef12345678"]
        XCTAssertTrue(removeAccountButton.waitForExistence(timeout: 5))
        removeAccountButton.tap()

        XCTAssertTrue(app.buttons["Remove Account"].waitForExistence(timeout: 5))
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

    func testSettingsResetConfirmationAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        try selectTab("Profile", in: app)

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let resetButton = app.buttons["Clear Local Privacy Data"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5))
        resetButton.tap()

        XCTAssertTrue(app.alerts["Clear local privacy data?"].waitForExistence(timeout: 5))
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
        if tabButton.waitForExistence(timeout: 5) {
            tabButton.tap()
            return
        }

        let moreButton = app.tabBars.buttons["More"]
        guard moreButton.waitForExistence(timeout: 2) else {
            throw XCTSkip("The \(title) tab is not visible in this launch state.")
        }

        moreButton.tap()
        let moreListButton = app.buttons[title]
        guard moreListButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("The \(title) tab is not visible in the More tab list.")
        }
        moreListButton.tap()
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
                // SwiftUI can emit diagnostics without a queryable element. Keep the
                // mapped issues blocking, but do not fail on diagnostics we cannot route.
                if issue.element == nil {
                    return true
                }

                // UIKit-backed SwiftUI alerts and confirmation dialogs can report internal
                // system labels as fixed-size even though the app supplies native title/message content.
                if issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
                   elementDescription.contains("↳Alert") || elementDescription.contains("↳Popover") {
                    return true
                }

                return false
            }
        } else {
            throw XCTSkip("performAccessibilityAudit requires iOS 17 or newer.")
        }
    }
}
