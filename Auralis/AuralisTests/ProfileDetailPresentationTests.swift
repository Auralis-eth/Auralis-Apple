@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import Testing

@MainActor
struct ProfileDetailPresentationTests {
    @Test(
        "presentation uses account identity and scoped counts",
        .disabled("Crashes in the Xcode 26 beta app-hosted runner because EOAccount is loaded from both the app and test bundles.")
    )
    func presentationUsesAccountIdentityAndCounts() {
        let account = EOAccount(
            address: "0x1111111111111111111111111111111111111111",
            name: "alpha.eth",
            source: .qrScan,
            addedAt: Date(timeIntervalSince1970: 100),
            lastSelectedAt: Date(timeIntervalSince1970: 200),
            trackedNFTCount: 12
        )

        let presentation = ProfileDetailView.makePresentation(
            account: account,
            accountAddress: account.address,
            currentChain: .ethMainnet,
            scopedNFTCount: 3,
            scopedTokenCount: 2,
            isCurrentAccount: true
        )

        #expect(presentation.title == "alpha.eth")
        #expect(presentation.sourceTitle == "QR")
        #expect(presentation.scopedNFTLabel == "3 NFTs")
        #expect(presentation.scopedTokenLabel == "2 tokens")
        #expect(presentation.isCurrentAccount)
    }

    @Test("presentation falls back when account data is unavailable")
    func presentationFallsBackWhenAccountDataIsUnavailable() {
        let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
        let presentation = ProfileDetailView.makePresentation(
            account: nil,
            accountAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            currentChain: .baseMainnet,
            scopedNFTCount: 0,
            scopedTokenCount: 1,
            isCurrentAccount: false,
            nowProvider: { referenceDate }
        )

        #expect(presentation.title == "Account 0xab")
        #expect(presentation.addressLine == "0xabcd...abcd")
        #expect(presentation.chainTitle == "Base scope")
        #expect(presentation.sourceTitle == "Imported")
        #expect(presentation.scopedNFTLabel == "0 NFTs")
        #expect(presentation.scopedTokenLabel == "1 token")
        #expect(presentation.activityLabel == "Last active Nov 14, 2023")
        #expect(presentation.isCurrentAccount == false)
    }

    @Test(
        "presentation trims blank account names before defaulting to address",
        .disabled("Crashes in the Xcode 26 beta app-hosted runner because EOAccount is loaded from both the app and test bundles.")
    )
    func presentationTrimsBlankAccountNamesBeforeDefaulting() {
        let account = EOAccount(
            address: "0x1111111111111111111111111111111111111111",
            name: "   ",
            source: .manualEntry,
            addedAt: Date(timeIntervalSince1970: 100),
            lastSelectedAt: nil,
            trackedNFTCount: 0
        )

        let presentation = ProfileDetailView.makePresentation(
            account: account,
            accountAddress: account.address,
            currentChain: .polygonMainnet,
            scopedNFTCount: 1,
            scopedTokenCount: 0,
            isCurrentAccount: true
        )

        #expect(presentation.title == "Account 0x11")
        #expect(presentation.sourceTitle == "Manual")
        #expect(presentation.scopedNFTLabel == "1 NFT")
        #expect(presentation.scopedTokenLabel == "0 tokens")
    }

    @Test(
        "presentation prefers most recent activity over the imported date",
        .disabled("Crashes in the Xcode 26 beta app-hosted runner because EOAccount is loaded from both the app and test bundles.")
    )
    func presentationPrefersMostRecentActivity() {
        let account = EOAccount(
            address: "0x1111111111111111111111111111111111111111",
            name: "Collector",
            source: .guestPass,
            addedAt: Date(timeIntervalSince1970: 100),
            lastSelectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            trackedNFTCount: 0
        )

        let presentation = ProfileDetailView.makePresentation(
            account: account,
            accountAddress: account.address,
            currentChain: .ethMainnet,
            scopedNFTCount: 0,
            scopedTokenCount: 0,
            isCurrentAccount: false
        )

        #expect(presentation.sourceTitle == "Guest Pass")
        #expect(presentation.activityLabel == "Last active Nov 14, 2023")
    }
}
