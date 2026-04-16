import Foundation

struct ERC20HoldingsSyncKey: Hashable {
    let accountAddress: String
    let chain: Chain
    let nativeBalanceDisplay: String?
    let updatedAt: Date?
    let refreshAnchor: Date?
}
