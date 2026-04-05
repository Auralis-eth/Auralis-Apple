import Foundation
import Testing
@testable import Auralis

@Suite
@MainActor
struct HomeTabLogicTests {
    private let logic = HomeTabLogic()

    @Test("logout clears the active selection while preserving persisted accounts")
    func logoutPlanClearsSessionWithoutDeletingRoster() {
        let plan = logic.logoutPlan()

        #expect(plan.shouldDeleteNFTs)
        #expect(plan.shouldDeleteTags)
        #expect(plan.shouldDeleteAccounts == false)
        #expect(plan.nextCurrentAddress.isEmpty)
    }

    @Test("home sparse-data state distinguishes first-run sparse and normal dashboards")
    func sparseDataStateUsesScopedLocalSignals() {
        #expect(
            logic.sparseDataState(scopedNFTCount: 0, recentActivityCount: 0) == .firstRun
        )
        #expect(
            logic.sparseDataState(scopedNFTCount: 3, recentActivityCount: 0) == .sparse
        )
        #expect(
            logic.sparseDataState(scopedNFTCount: 0, recentActivityCount: 2) == .sparse
        )
        #expect(
            logic.sparseDataState(scopedNFTCount: 3, recentActivityCount: 2) == .normal
        )
    }

    @Test("home sparse-state presentation does not appear during loading or failure conditions")
    func sparseStatePresentationDefersToLoadingAndFailure() {
        #expect(
            logic.sparseStatePresentation(
                scopedNFTCount: 0,
                recentActivityCount: 0,
                isHomeLoading: true,
                isShowingFailure: false
            ) == nil
        )
        #expect(
            logic.sparseStatePresentation(
                scopedNFTCount: 0,
                recentActivityCount: 0,
                isHomeLoading: false,
                isShowingFailure: true
            ) == nil
        )
    }

    @Test("first-run and sparse Home states map only to real existing routes")
    func sparseStatePresentationUsesRealNextActions() {
        #expect(
            logic.sparseStatePresentation(
                scopedNFTCount: 0,
                recentActivityCount: 0,
                isHomeLoading: false,
                isShowingFailure: false
            ) == HomeSparseStatePresentation(
                state: .firstRun,
                primaryAction: .openSearch,
                secondaryAction: .switchAccount
            )
        )
        #expect(
            logic.sparseStatePresentation(
                scopedNFTCount: 1,
                recentActivityCount: 0,
                isHomeLoading: false,
                isShowingFailure: false
            ) == HomeSparseStatePresentation(
                state: .sparse,
                primaryAction: .openSearch,
                secondaryAction: .openNews
            )
        )
    }

    @Test("first-run Home presentation is deterministic and clears once local data exists")
    func sparseStatePresentationClearsOnceDashboardHasData() {
        let firstRunPresentation = logic.sparseStatePresentation(
            scopedNFTCount: 0,
            recentActivityCount: 0,
            isHomeLoading: false,
            isShowingFailure: false
        )

        #expect(firstRunPresentation?.state == .firstRun)
        #expect(firstRunPresentation?.primaryAction == .openSearch)
        #expect(firstRunPresentation?.secondaryAction == .switchAccount)

        let clearedPresentation = logic.sparseStatePresentation(
            scopedNFTCount: 2,
            recentActivityCount: 2,
            isHomeLoading: false,
            isShowingFailure: false
        )

        #expect(clearedPresentation == nil)
    }

    @Test("account summary presentation uses trustworthy account and scope fields and degrades cleanly")
    func accountSummaryPresentationUsesOwnedFields() {
        let summary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: "Primary Wallet",
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .baseMainnet,
                scopedNFTCount: 3,
                mostRecentActivityAt: Date(timeIntervalSince1970: 200)
            )
        )

        #expect(summary.title == "Primary Wallet")
        #expect(summary.addressLine == "0x1234...5678")
        #expect(summary.chainTitle == "Base scope")
        #expect(summary.trackedNFTLabel == "3 scoped NFTs")
        #expect(summary.lastActivityLabel != nil)
    }

    @Test("account summary presentation falls back cleanly when optional values are absent")
    func accountSummaryPresentationDegradesCleanly() {
        let summary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: nil,
                address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                chain: .ethMainnet,
                scopedNFTCount: 0,
                mostRecentActivityAt: nil
            )
        )

        #expect(summary.title == "Active Account")
        #expect(summary.addressLine == "0xabcd...abcd")
        #expect(summary.chainTitle == "Ethereum scope")
        #expect(summary.trackedNFTLabel == "No scoped NFTs yet")
        #expect(summary.lastActivityLabel == nil)
    }

    @Test("account summary presentation updates when account or chain scope changes")
    func accountSummaryPresentationTracksAccountAndChainSwitches() {
        let firstSummary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: "Primary Wallet",
                address: "0x1234567890abcdef1234567890abcdef12345678",
                chain: .ethMainnet,
                scopedNFTCount: 2,
                mostRecentActivityAt: nil
            )
        )
        let secondSummary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: "Travel Wallet",
                address: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                chain: .baseMainnet,
                scopedNFTCount: 1,
                mostRecentActivityAt: nil
            )
        )

        #expect(firstSummary.title == "Primary Wallet")
        #expect(firstSummary.chainTitle == "Ethereum scope")
        #expect(secondSummary.title == "Travel Wallet")
        #expect(secondSummary.addressLine == "0xabcd...abcd")
        #expect(secondSummary.chainTitle == "Base scope")
    }

    @Test("account summary card remains useful when richer activity data is absent")
    func accountSummaryPresentationRemainsUsefulWithoutActivity() {
        let summary = logic.accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: "Observe Wallet",
                address: "0x9999999999999999999999999999999999999999",
                chain: .ethMainnet,
                scopedNFTCount: 4,
                mostRecentActivityAt: nil
            )
        )

        #expect(summary.title == "Observe Wallet")
        #expect(summary.addressLine == "0x9999...9999")
        #expect(summary.chainTitle == "Ethereum scope")
        #expect(summary.trackedNFTLabel == "4 scoped NFTs")
        #expect(summary.lastActivityLabel == nil)
    }
}
