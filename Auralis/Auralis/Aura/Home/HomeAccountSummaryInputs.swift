import Foundation

struct HomeAccountSummaryInputs: Equatable {
    let accountName: String?
    let address: String
    let chain: Chain
    let scopedNFTCount: Int
    let mostRecentActivityAt: Date?
}
