import Testing
@testable import Auralis

@Suite
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
}
