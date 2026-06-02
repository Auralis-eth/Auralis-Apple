import AuralisPrimaryModels
import Foundation

public extension TokenHolding {
    static let hiddenAmountDisplay = "Amount hidden"

    var hidesAmountUntilMetadataLoads: Bool {
        amountDisplay == Self.hiddenAmountDisplay
    }

    var hasStaleMetadata: Bool {
        hasStaleMetadata(referenceDate: .now)
    }

    func hasStaleMetadata(referenceDate: Date) -> Bool {
        balanceKind == .erc20 && TokenHoldingsMetadataFreshnessPolicy.isStale(updatedAt: updatedAt, now: referenceDate)
    }
}
