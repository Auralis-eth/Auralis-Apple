import Foundation

protocol GasPricingProviding {
    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimate
}
