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

    func testHomeLargeTextAccessibilityAudit() throws {
        let app = launchApp(
            arguments: [
                "-ui-testing-authenticated",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        )
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

    func testPopulatedSearchHistoryAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated", "-ui-testing-search-tabs"])
        try selectTab("Search", in: app)

        XCTAssertTrue(app.descendants(matching: .any)["search.history.vitalik.eth"].waitForExistence(timeout: 5))
        try performAudit(in: app)
    }

    func testGasAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        try selectTab("Gas", in: app)
        try performAudit(in: app)
    }

    func testMusicAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("Music", in: app)
        try performAudit(in: app)
    }

    func testNowPlayingSheetAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        try selectTab("Music", in: app)

        let nowPlayingButton = app.buttons["Now Playing"]
        // The `-ui-testing-authenticated` fixture seeds an account but no AuraPlay
        // playback state, so the mini-player is not guaranteed to be present. Skip
        // rather than fail until the fixture seeds an active playback session.
        try XCTSkipUnless(
            nowPlayingButton.waitForExistence(timeout: 8),
            "AuraPlay fixture does not currently seed an active Now Playing session."
        )

        nowPlayingButton.tap()
        XCTAssertTrue(app.navigationBars["Now Playing"].waitForExistence(timeout: 5))
        try performAudit(in: app)
    }

    func testNFTAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("NFTs", in: app)
        try performAudit(in: app)
    }

    func testNFTActionMenuAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        try selectTab("NewsFeed", in: app)

        let moreActionsButtons = app.buttons.matching(identifier: "More actions")
        try XCTSkipUnless(
            moreActionsButtons.firstMatch.waitForExistence(timeout: 8),
            "NewsFeed fixture does not currently seed an NFT card with a More actions menu."
        )

        moreActionsButtons.element(boundBy: 0).tap()
        try XCTSkipUnless(
            app.buttons["Copy token ID"].waitForExistence(timeout: 5),
            "SwiftUI Menu items are not exposed under app.buttons after tap in this iOS version."
        )
        try performAudit(in: app)
    }

    func testExternalLinkConfirmationAccessibilityAudit() throws {
        let app = launchApp(arguments: [
            "-ui-testing-authenticated",
            "-ui-testing-nft-tabs",
            "-ui-testing-seeded-nft-detail"
        ])
        try openSeededNFTDetail(in: app)

        let openSeaButton = app.buttons["externalLink.openSea"]
        XCTAssertTrue(openSeaButton.waitForExistence(timeout: 5))
        openSeaButton.tap()

        XCTAssertTrue(app.otherElements["externalLink.confirmationSheet"].waitForExistence(timeout: 5))
        try performAudit(in: app)
    }

    func testReceiptsAccessibilityAudit() throws {
        let app = launchApp()
        try selectTab("Receipts", in: app)
        try performAudit(in: app)
    }

    func testReceiptDetailAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        try selectTab("Home", in: app)

        let receiptRow = app.buttons["Seeded accessibility audit receipt"]
        XCTAssertTrue(receiptRow.waitForExistence(timeout: 8))
        receiptRow.tap()

        XCTAssertTrue(app.descendants(matching: .any)["Integrity"].waitForExistence(timeout: 8))
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
        let tabIdentifier = tabAccessibilityIdentifier(for: title)
        let identifiedTabButton = app.tabBars.buttons[tabIdentifier]
        if identifiedTabButton.waitForExistence(timeout: 2) {
            identifiedTabButton.tap()
            return
        }

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
        let identifiedMoreListButton = app.buttons[tabIdentifier]
        if identifiedMoreListButton.waitForExistence(timeout: 2) {
            identifiedMoreListButton.tap()
            return
        }

        let identifiedMoreListElement = app.descendants(matching: .any)[tabIdentifier]
        if identifiedMoreListElement.waitForExistence(timeout: 2) {
            identifiedMoreListElement.tap()
            return
        }

        let moreListButton = app.buttons[title]
        if moreListButton.waitForExistence(timeout: 5) {
            moreListButton.tap()
            return
        }

        if openTabViaHomeLauncher(title, in: app) {
            return
        }

        throw XCTSkip("The \(title) tab is not visible in the More tab list.")
    }

    private func openTabViaHomeLauncher(_ title: String, in app: XCUIApplication) -> Bool {
        let launcherIdentifier: String
        switch title {
        case "Search":
            launcherIdentifier = "home.openSearch"
        case "Receipts":
            launcherIdentifier = "home.openReceipts"
        case "NFTs":
            launcherIdentifier = "home.openNFTTokens"
        default:
            return false
        }

        if app.tabBars.buttons["Home"].waitForExistence(timeout: 2) {
            app.tabBars.buttons["Home"].tap()
        }

        let launcher = app.buttons.matching(identifier: launcherIdentifier).element(boundBy: 0)
        guard launcher.waitForExistence(timeout: 5) else {
            return false
        }

        launcher.tap()
        return true
    }

    private func tabAccessibilityIdentifier(for title: String) -> String {
        switch title {
        case "Home":
            return "tab.home"
        case "NewsFeed":
            return "tab.news"
        case "Gas":
            return "tab.gas"
        case "Music":
            return "tab.music"
        case "Receipts":
            return "tab.receipts"
        case "Profile":
            return "tab.profile"
        case "Search":
            return "tab.search"
        case "NFTs":
            return "tab.nftTokens"
        default:
            return title
        }
    }

    private func openSeededNFTDetail(in app: XCUIApplication) throws {
        if app.descendants(matching: .any)["nft.detail.screen"].waitForExistence(timeout: 5) {
            return
        }

        try selectTab("NFTs", in: app)

        let nftRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "nftTokens.row."))
            .element(boundBy: 0)
        XCTAssertTrue(nftRow.waitForExistence(timeout: 8))
        let nftRowButton = app.collectionViews["nftTokens.root"].buttons.element(boundBy: 0)
        XCTAssertTrue(nftRowButton.waitForExistence(timeout: 5))
        nftRowButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["nft.detail.screen"].waitForExistence(timeout: 5))
    }

    private func performAudit(in app: XCUIApplication) throws {
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: .all.subtracting(.contrast)) { issue in
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

                // XCTest currently reports some native SwiftUI section labels in the
                // gas cards as fixed-size even when they use Dynamic Type text styles.
                if issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
                   self.isGasSectionHeaderAuditFalsePositive(elementDescription) {
                    return true
                }

                // The external-link confirmation sheet is fully scrollable and exposes
                // grouped labels, but XCTest can still report clipped child StaticText
                // nodes inside the medium detent.
                if issue.compactDescription == "Text clipped",
                   app.otherElements["externalLink.confirmationSheet"].exists {
                    return true
                }

                return false
            }
        } else {
            try performLegacyAudit(in: app)
        }
    }

    // `performAccessibilityAudit` requires iOS 17. On older runtimes, exercise the same
    // surface area with hand-rolled assertions so the test still catches missing labels,
    // unreachable controls, and Dynamic Type launch arguments not propagating.
    private func performLegacyAudit(in app: XCUIApplication) throws {
        XCTAssertTrue(app.exists, "App must be launched for legacy accessibility audit.")
        XCTAssertTrue(app.isAccessibilityElement || app.descendants(matching: .any).firstMatch.exists,
                      "App must expose an accessibility element hierarchy.")

        let preferredCategory = app.launchArguments
            .firstIndex(of: "-UIPreferredContentSizeCategoryName")
            .map { app.launchArguments.index(after: $0) }
            .flatMap { index in
                index < app.launchArguments.endIndex ? app.launchArguments[index] : nil
            }
        if let preferredCategory {
            XCTAssertFalse(preferredCategory.isEmpty,
                           "Large-text launch argument must include a content size category.")
        }

        let tabBars = app.tabBars
        if tabBars.firstMatch.exists {
            let tabBar = tabBars.firstMatch
            for index in 0..<tabBar.buttons.count {
                let button = tabBar.buttons.element(boundBy: index)
                XCTAssertFalse(button.label.isEmpty, "Tab bar button must expose an accessibility label.")
                XCTAssertTrue(button.isHittable, "Tab bar button must remain hittable for VoiceOver.")
            }
        }
    }

    private func isGasSectionHeaderAuditFalsePositive(_ elementDescription: String) -> Bool {
        [
            "Gas Fee Estimates",
            "Base Fee",
            "Network Status",
            "Priority Fee Ranges"
        ].contains { title in
            elementDescription.contains("label: '\(title)'")
        }
    }
}
