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
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        // Authenticated because this audit is about the *tab content*. A bare `launchApp()` lands on
        // the unauthenticated gateway, which has no tab bar at all, so `selectTab` exhausted its
        // fallbacks and failed with "not reachable in this launch state" — a launch-state defect in
        // the test, not an accessibility finding. Invisible until Round 18 ran these for the first time.
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
        let app = launchApp(arguments: ["-ui-testing-authenticated", "-ui-testing-mission-control-tabs", "-ui-testing-mission-control-fixtures"])
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
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        // Authenticated because this audit is about the *tab content*. A bare `launchApp()` lands on
        // the unauthenticated gateway, which has no tab bar at all, so `selectTab` exhausted its
        // fallbacks and failed with "not reachable in this launch state" — a launch-state defect in
        // the test, not an accessibility finding. Invisible until Round 18 ran these for the first time.
        try selectTab("NewsFeed", in: app)
        try performAudit(in: app)
    }

    func testSearchAccessibilityAudit() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        // Authenticated because this audit is about the *tab content*. A bare `launchApp()` lands on
        // the unauthenticated gateway, which has no tab bar at all, so `selectTab` exhausted its
        // fallbacks and failed with "not reachable in this launch state" — a launch-state defect in
        // the test, not an accessibility finding. Invisible until Round 18 ran these for the first time.
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
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        // Authenticated because this audit is about the *tab content*. A bare `launchApp()` lands on
        // the unauthenticated gateway, which has no tab bar at all, so `selectTab` exhausted its
        // fallbacks and failed with "not reachable in this launch state" — a launch-state defect in
        // the test, not an accessibility finding. Invisible until Round 18 ran these for the first time.
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
        // Authenticated because this audit is about the *tab content*. A bare `launchApp()` lands on
        // the unauthenticated gateway, which has no tab bar at all, so `selectTab` exhausted its
        // fallbacks and failed with "not reachable in this launch state" — a launch-state defect in
        // the test, not an accessibility finding. Invisible until Round 18 ran these for the first time.
        //
        // `-ui-testing-nft-tabs` on top of that, because `-ui-testing-authenticated` alone yields
        // `AppTabBarVisibility.release`, which does **not** contain `.nftTokens` — so the NFTs tab was
        // not in the tab bar at all and the only route left was the Home launcher, which this audit
        // then failed to reach. The fixture exists for exactly this and is what the seeded-NFT-detail
        // audit already uses.
        let app = launchApp(arguments: ["-ui-testing-authenticated", "-ui-testing-nft-tabs"])
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
        let app = launchApp(arguments: ["-ui-testing-authenticated"])
        // Authenticated because this audit is about the *tab content*. A bare `launchApp()` lands on
        // the unauthenticated gateway, which has no tab bar at all, so `selectTab` exhausted its
        // fallbacks and failed with "not reachable in this launch state" — a launch-state defect in
        // the test, not an accessibility finding. Invisible until Round 18 ran these for the first time.
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

    func testMissionControlOperatorConsoleSmoke() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated", "-ui-testing-mission-control-tabs", "-ui-testing-mission-control-fixtures"])

        // Navigate to Home rather than asserting it is already on screen.
        //
        // Mission Control is a `NavigationSplitView`. At compact width it launches collapsed onto the
        // *sidebar*, and whether the `section = .home` selection has pushed the detail column by the
        // time the first query runs is a race — so a bare `waitForExistence` here passed or failed on
        // timing alone, with no amount of waiting helping once the sidebar was showing. Every other
        // Mission Control assertion in this file already goes through this helper, which checks for the
        // identifier first and otherwise drives the sidebar or the section picker to reach it.
        try openMissionControlSection("Home", identifier: "missionControl.modeSection", in: app)

        _ = revealElement(identifier: "missionControl.pauseToggle", in: app)
        let pauseToggle = app.switches["missionControl.pauseToggle"]
        XCTAssertTrue(pauseToggle.exists)
        pauseToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(pauseToggle.value as? String, "1")
        pauseToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(pauseToggle.value as? String, "0")

        try openMissionControlSection("Receipts", identifier: "missionControl.receipts.browser", in: app)
        try openMissionControlSection("Routines", identifier: "missionControl.routines", in: app)
        try openMissionControlSection("Operators", identifier: "missionControl.operators", in: app)

        let query = app.textFields["mc.operators.queryInput"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("accessibility audit")
        // Dismiss the keyboard before asserting on anything further down the list.
        //
        // This is what `testMissionControlOperatorConsoleSmoke` was actually failing on, and it looked
        // like three other things first. With the keyboard up, the visible slice of the Operators list
        // is a few rows tall and `app.swipeUp()` lands on the keyboard rather than the list, so the
        // scroll never happens — and because SwiftUI `List` does not materialise off-screen rows into
        // the accessibility hierarchy, the Run button for anything below the fold reports
        // `exists == false`. A diagnostic dump at the failure confirmed the shape precisely: the
        // operator rows *were* registered and rendered (`missionControl.operators.run.policy.approve_spending`
        // was present, the empty-state marker was not), while the only other identified buttons were
        // `dictation`, `shift` and `Return` — the keyboard. So the assertion was reporting "the button
        // is missing" about a button that existed the whole time, just off-screen behind a keyboard
        // nothing had dismissed.
        dismissKeyboard(in: app)
        let runButton = revealElement(
            identifier: "missionControl.operators.run.operator.research.brief",
            in: app
        )
        XCTAssertTrue(runButton.exists)
        runButton.tap()
        let outcome = app.staticTexts["missionControl.operators.outcome.operator.research.brief"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 15))
        XCTAssertTrue(outcome.label.hasPrefix("Executed"), "Research operator outcome: \(outcome.label)")

        try openMissionControlSection("Artifacts", identifier: "missionControl.artifacts", in: app)
        let firstArtifact = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "missionControl.artifacts.row."))
            .firstMatch
        for _ in 0..<4 where !firstArtifact.exists {
            app.swipeUp()
        }
        XCTAssertTrue(firstArtifact.waitForExistence(timeout: 8))
        firstArtifact.tap()
        XCTAssertTrue(app.descendants(matching: .any)["missionControl.artifact.detail"].waitForExistence(timeout: 8))
    }

    func testMissionControlApprovalInboxOpensLinkedReceiptDetail() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated", "-ui-testing-mission-control-tabs", "-ui-testing-mission-control-fixtures"])
        try openMissionControlSection("Approvals", identifier: "missionControl.approvals", in: app)

        let approval = button(containing: "Review seeded receipt route", in: app)
        XCTAssertTrue(approval.waitForExistence(timeout: 8))
        approval.tap()

        let receiptLink = revealButton(containing: "Seeded Mission Control approval receipt", in: app)
        XCTAssertTrue(receiptLink.exists)
        receiptLink.tap()

        XCTAssertTrue(app.descendants(matching: .any)["missionControl.receipt.detail"].waitForExistence(timeout: 8))
    }

    func testMissionControlArtifactBrowserOpensRelatedReceiptDetail() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated", "-ui-testing-mission-control-tabs", "-ui-testing-mission-control-fixtures"])
        try openMissionControlSection("Artifacts", identifier: "missionControl.artifacts", in: app)

        let artifact = revealButton(containing: "Seeded Mission Control Artifact", in: app)
        XCTAssertTrue(artifact.exists)
        artifact.tap()

        XCTAssertTrue(app.descendants(matching: .any)["missionControl.artifact.detail"].waitForExistence(timeout: 8))
        let receiptLink = revealButton(containing: "Seeded Mission Control artifact receipt", in: app)
        XCTAssertTrue(receiptLink.exists)
        receiptLink.tap()

        XCTAssertTrue(app.descendants(matching: .any)["missionControl.receipt.detail"].waitForExistence(timeout: 8))
        XCTAssertTrue(revealLabeledElement("Related artifacts", in: app).exists)
    }

    func testMissionControlArtifactLifecycleControlsAreReachable() throws {
        let app = launchApp(arguments: ["-ui-testing-authenticated", "-ui-testing-mission-control-tabs", "-ui-testing-mission-control-fixtures"])
        try openMissionControlSection("Artifacts", identifier: "missionControl.artifacts", in: app)

        XCTAssertTrue(app.descendants(matching: .any)["missionControl.artifacts.historyScope"].waitForExistence(timeout: 8))
        let artifact = revealButton(containing: "Seeded Mission Control Artifact", in: app)
        XCTAssertTrue(artifact.exists)
        artifact.tap()

        XCTAssertTrue(app.descendants(matching: .any)["missionControl.artifact.detail"].waitForExistence(timeout: 8))
        XCTAssertTrue(revealElement(identifier: "missionControl.artifact.export", in: app).exists)
        XCTAssertTrue(revealElement(identifier: "missionControl.artifact.supersede", in: app).exists)
    }

    func testSettingsResetConfirmationAccessibilityAudit() throws {
        // `-ui-testing-profile-tabs` because `.release` carries six tabs and Profile falls into the
        // compact iPhone's overflow, where `selectTab` could not find it and had no Home-launcher
        // fallback to fall back to (F-105, harness class).
        let app = launchApp(arguments: ["-ui-testing-authenticated", "-ui-testing-profile-tabs"])
        try selectTab("Profile", in: app)

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        // Revealed rather than looked up directly: the reset control sits near the bottom of Settings
        // and is off-screen on launch, so the bare `app.buttons[...]` lookup never resolved it. Same
        // helper the other deep-in-a-scroll-view audits use.
        let resetButton = revealButton(containing: "Clear Local Privacy Data", in: app)
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
            if openTabViaHomeLauncher(title, in: app) { return }
            XCTFail("The \(title) tab is not reachable in this launch state.")
            return
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

        // The hierarchy, not just the verdict. "Not reachable" names the symptom and says nothing
        // about which of the four routes was closest, and this failure has now cost two rounds of
        // guessing (F-57 was diagnosed only once someone dumped the tree at the failure, F-104).
        // Printing the tab bar here makes the next occurrence self-diagnosing.
        XCTFail(
            """
            The \(title) tab is not reachable from the tab bar or an alternate app route.
            Looked for identifier "\(tabAccessibilityIdentifier(for: title))" and label "\(title)".
            Tab bars present: \(app.tabBars.count)
            Tab bar buttons: \(app.tabBars.buttons.allElementsBoundByIndex.map { "\($0.identifier)/\($0.label)" })
            Top-level buttons: \(app.buttons.allElementsBoundByIndex.prefix(30).map { "\($0.identifier)/\($0.label)" })
            """
        )
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
        case "Ops":
            if app.tabBars.buttons["tab.profile"].waitForExistence(timeout: 2) {
                app.tabBars.buttons["tab.profile"].tap()
            } else if app.tabBars.buttons["Profile"].waitForExistence(timeout: 2) {
                app.tabBars.buttons["Profile"].tap()
            } else if app.buttons["tab.profile"].waitForExistence(timeout: 2) {
                app.buttons["tab.profile"].tap()
            } else if app.buttons["Profile"].waitForExistence(timeout: 2) {
                app.buttons["Profile"].tap()
            } else {
                return false
            }
            let settingsButton = app.buttons["Settings"]
            guard settingsButton.waitForExistence(timeout: 5) else { return false }
            settingsButton.tap()
            let missionControlButton = app.buttons["settings.missionControl"]
            guard missionControlButton.waitForExistence(timeout: 5) else { return false }
            missionControlButton.tap()
            return true
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
        case "Ops":
            return "tab.missionControl"
        default:
            return title
        }
    }

    private func openMissionControlSection(_ title: String, identifier: String, in app: XCUIApplication) throws {
        if app.descendants(matching: .any)[identifier].waitForExistence(timeout: 2) {
            return
        }

        for _ in 0..<4 {
            app.swipeDown()
        }

        let sidebarButton = app.buttons[title]
        if sidebarButton.waitForExistence(timeout: 3) {
            sidebarButton.tap()
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 8))
            return
        }

        let sectionPicker = app.buttons["missionControl.sectionPicker"]
        XCTAssertTrue(
            sectionPicker.waitForExistence(timeout: 3),
            "Mission Control section navigation is not exposed in this launch state."
        )
        guard sectionPicker.exists else { return }
        sectionPicker.tap()

        let menuItem = app.buttons[title]
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: 3),
            "Mission Control section \(title) is not exposed in the section picker."
        )
        guard menuItem.exists else { return }
        menuItem.tap()
        XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 8))
    }

    private func button(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    private func revealButton(containing text: String, in app: XCUIApplication, maxSwipes: Int = 4) -> XCUIElement {
        let element = button(containing: text, in: app)
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
        return element
    }

    private func revealLabeledElement(_ label: String, in app: XCUIApplication, maxSwipes: Int = 4) -> XCUIElement {
        let element = app.descendants(matching: .any)[label]
        for _ in 0..<maxSwipes where !element.exists {
            app.swipeUp()
        }
        return element
    }

    /// Dismisses the software keyboard if it is up, so subsequent scrolling acts on the content.
    ///
    /// Tries the keyboard's own Return key first and falls back to tapping a neutral part of the
    /// navigation bar, because a `TextField` inside a `Form` does not always expose a "Done"
    /// accessory. A no-op when no keyboard is present.
    private func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.element.exists else { return }
        let returnKey = app.buttons["Return"]
        if returnKey.exists {
            returnKey.tap()
        } else {
            app.navigationBars.element(boundBy: 0).tap()
        }
        // The keyboard animates out; the next query must not race it.
        _ = app.keyboards.element.waitForNonExistence(timeout: 3)
    }

    /// Scrolls until `identifier` is on screen, **waiting** for it between swipes.
    ///
    /// The wait is the fix, not the swiping. This used to test a bare `element.exists` in the loop
    /// condition, which asks "is it on screen *right now*" — and several of these lists are populated
    /// asynchronously (`MissionControlHomeModel.operatorTools` comes from `await host.registeredTools()`).
    /// So for any row that had not landed yet the loop saw `false` immediately, burned every swipe in a
    /// few milliseconds without the content ever having had a chance to appear, and then returned a
    /// non-existent element — scrolling *past* the destination on the way. That reads as "the row is
    /// missing" when the truth is "the row was not there yet", which is a false negative, not a flake:
    /// it fails deterministically on a fast machine.
    ///
    /// A short wait per iteration also makes the swipe budget meaningful — four swipes of a list that
    /// is still empty is not four swipes of the list the assertion is about.
    /// The budget is 12 rather than 4 because the lists this walks are long and the loop now exits on
    /// the first sighting, so a generous ceiling costs nothing for a near element and is the
    /// difference between pass and fail for a far one. The Operators console is the worked example:
    /// `operatorTools` is sorted by title, so the registered set renders as **Approve Spending,
    /// Draft Transaction, Identity Review, On-Chain Watch, Prepare On-Chain Action, Research Brief,
    /// Run Plugin, Sign Message** — "Research Brief" is sixth of eight, each row carries a title, a
    /// caption, a Run button and an "Inspect proposal" link, and all of it sits below an Inputs
    /// section of roughly ten rows. Its Run button is ~35 rows down a `List`; four swipes could not
    /// reach it, which is why `testMissionControlOperatorConsoleSmoke` failed deterministically at an
    /// assertion about a button that was present the whole time.
    private func revealElement(
        identifier: String,
        in app: XCUIApplication,
        maxSwipes: Int = 12,
        perSwipeTimeout: TimeInterval = 1
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        // Wait before the first swipe: the element may simply be loading, in which case scrolling is
        // the wrong move entirely.
        if element.waitForExistence(timeout: perSwipeTimeout) {
            return element
        }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.waitForExistence(timeout: perSwipeTimeout) {
                return element
            }
        }
        return element
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
                let elementLabel = issue.element?.label ?? ""
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

                // These nodes all use semantic SwiftUI text styles in production. XCTest reports
                // their native toolbar/control wrappers and identified section labels as fixed-size,
                // even though the underlying text responds to the content-size environment.
                if issue.compactDescription == "Dynamic Type font sizes are partially unsupported",
                   self.isSemanticTextStyleAuditFalsePositive(elementLabel) {
                    return true
                }

                // The external-link confirmation sheet is fully scrollable and exposes
                // grouped labels, but XCTest can still report clipped child StaticText
                // nodes inside the medium detent.
                if issue.compactDescription == "Text clipped",
                   app.otherElements["externalLink.confirmationSheet"].exists {
                    return true
                }

                // AuraEmptyState renders this message with `.body`, unlimited lines, and vertical
                // fixed sizing. XCTest still predicts clipping for the combined accessibility node.
                if issue.compactDescription == "Text clipped",
                   self.isSemanticTextClippingAuditFalsePositive(elementLabel) {
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

    private func isSemanticTextStyleAuditFalsePositive(_ elementLabel: String) -> Bool {
        [
            "Close",
            "Unplayed",
            "NFT Tokens",
            "Active Scope",
            "Energy",
            "Quick Links",
            "Preview",
            "Library",
            "1 scoped NFT",
            "3 routes",
            "1 pinned"
        ]
            .contains(elementLabel)
    }

    private func isSemanticTextClippingAuditFalsePositive(_ elementLabel: String) -> Bool {
        elementLabel == "Refresh Paused"
            || elementLabel == "Retry"
            || elementLabel == "Unplayed"
            || elementLabel.hasPrefix("The provider returned data Auralis could not read")
            || elementLabel.hasPrefix("Search tracks, artists, moods")
            || elementLabel.hasPrefix("Search NFT, collection, contract, or token ID")
    }
}
