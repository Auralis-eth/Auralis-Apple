import AuralisPrimaryModels
import Foundation

public struct GasPriceEstimateResult: Sendable {
    public enum Source: Sendable {
        case live
        case cache
        case staleCache
    }

    public let estimate: GasPriceEstimate
    public let fetchedAt: Date
    public let source: Source

    public init(estimate: GasPriceEstimate, fetchedAt: Date, source: Source) {
        self.estimate = estimate
        self.fetchedAt = fetchedAt
        self.source = source
    }
}

public protocol GasPricingProviding: Sendable {
    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimateResult
}
