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
}
