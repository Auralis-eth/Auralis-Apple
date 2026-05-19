import AccountsFeature
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import Testing

@Suite
struct AccountSwitcherPresenterTests {
    private let presenter = AccountSwitcherPresenter()

    @Test("account switcher orders selected accounts by last selection then recency")
    func accountSwitcherOrdersAccountsForDisplay() {
        let oldest = makeAccount(
            address: "0x3333333333333333333333333333333333333333",
            addedAt: Date(timeIntervalSince1970: 100),
            lastSelectedAt: nil
        )
        let mostRecentlyAdded = makeAccount(
            address: "0x2222222222222222222222222222222222222222",
            addedAt: Date(timeIntervalSince1970: 300),
            lastSelectedAt: nil
        )
        let previouslySelected = makeAccount(
            address: "0x1111111111111111111111111111111111111111",
            addedAt: Date(timeIntervalSince1970: 200),
            lastSelectedAt: Date(timeIntervalSince1970: 400)
        )

        let sorted = presenter.sortedAccounts([oldest, mostRecentlyAdded, previouslySelected])

        #expect(sorted.map(\.address) == [
            "0x1111111111111111111111111111111111111111",
            "0x2222222222222222222222222222222222222222",
            "0x3333333333333333333333333333333333333333"
        ])
    }

    @Test("account switcher uses address as stable tie breaker")
    func accountSwitcherUsesAddressTieBreaker() {
        let sameDate = Date(timeIntervalSince1970: 100)
        let b = makeAccount(address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", addedAt: sameDate)
        let a = makeAccount(address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", addedAt: sameDate)

        let sorted = presenter.sortedAccounts([b, a])

        #expect(sorted.map(\.address) == [
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        ])
    }

    @Test("chain scope planner suppresses no-op writes and marks active scope refreshes")
    func chainScopePlannerKeepsAccountSwitchingWritesIntentional() {
        let planner = ChainScopeChangePlanner()
        let unchanged = planner.planPreferredChange(
            address: "0x1111111111111111111111111111111111111111",
            from: .ethMainnet,
            to: .ethMainnet
        )
        let currentChange = planner.planCurrentChange(
            address: "0x1111111111111111111111111111111111111111",
            from: .ethMainnet,
            to: .baseMainnet
        )

        #expect(unchanged.shouldApply == false)
        #expect(unchanged.event == nil)
        #expect(currentChange.shouldApply)
        #expect(currentChange.shouldRefreshActiveScope)
    }

    private func makeAccount(
        address: String,
        addedAt: Date,
        lastSelectedAt: Date? = nil
    ) -> EOAccount {
        EOAccount(
            address: address,
            addedAt: addedAt,
            lastSelectedAt: lastSelectedAt
        )
    }
}
