import AuralisPrimaryModels
import Foundation

public struct HomeAccountSummaryInputs: Equatable, Sendable {
    public let accountName: String?
    public let address: String
    public let chain: Chain
    public let scopedNFTCount: Int
    public let mostRecentActivityAt: Date?

    public init(
        accountName: String?,
        address: String,
        chain: Chain,
        scopedNFTCount: Int,
        mostRecentActivityAt: Date?
    ) {
        self.accountName = accountName
        self.address = address
        self.chain = chain
        self.scopedNFTCount = scopedNFTCount
        self.mostRecentActivityAt = mostRecentActivityAt
    }
}
