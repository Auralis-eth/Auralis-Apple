@testable import Auralis
import Foundation
import Testing

@Suite
struct ProfileDetailPresentationTests {
    @Test("presentation uses account identity and scoped counts")
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
}
