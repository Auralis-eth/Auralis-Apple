import AccountsFeature
import AuralisPrimaryModels
import Foundation
import Testing

@Suite
struct AccountSummaryPresenterTests {
    private let presenter = AccountSummaryPresenter()

    @Test("account summary presentation uses trustworthy account and scope fields")
    func accountSummaryPresentationUsesOwnedFields() {
        let summary = presenter.presentation(
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
        let summary = presenter.presentation(
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
}
