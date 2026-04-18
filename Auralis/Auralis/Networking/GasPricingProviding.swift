import Foundation

protocol GasPricingProviding: Sendable {
    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimate
}
