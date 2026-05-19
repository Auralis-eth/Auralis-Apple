import AuralisPrimaryModels
import Foundation

public extension TokenHolding {
    static let hiddenAmountDisplay = "Amount hidden"

    var hidesAmountUntilMetadataLoads: Bool {
        amountDisplay == Self.hiddenAmountDisplay
    }

    var hasStaleMetadata: Bool {
        balanceKind == .erc20 && TokenHoldingsMetadataFreshnessPolicy.isStale(updatedAt: updatedAt)
    }
}
