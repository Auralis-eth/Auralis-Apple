import AuralisPrimaryModels
import Foundation

struct GasPriceEstimateResult: Sendable {
    enum Source: Sendable {
        case live
        case cache
        case staleCache
    }

    let estimate: GasPriceEstimate
    let fetchedAt: Date
    let source: Source
}

protocol GasPricingProviding: Sendable {
    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimateResult
}
