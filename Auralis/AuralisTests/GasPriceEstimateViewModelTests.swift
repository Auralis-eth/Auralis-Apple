@testable import Auralis
import Foundation
import Testing

@Suite
@MainActor
struct GasPriceEstimateViewModelTests {
    @Test("setting the first chain immediately enters a non-error loading phase")
    func initialChainSelectionStartsInLoadingPhase() {
        let viewModel = GasPriceEstimateViewModel(provider: SlowGasPricingProvider())

        viewModel.setChain(.ethMainnet)

        #expect(viewModel.phase == .loading)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
        #expect(viewModel.estimate == nil)
    }

    @Test("failed fetches transition into the failed phase after the initial loading state")
    func failedFetchTransitionsToFailedPhase() async throws {
        let viewModel = GasPriceEstimateViewModel(provider: FailingGasPricingProvider())

        viewModel.setChain(.ethMainnet)

        #expect(viewModel.phase == .loading)

        for _ in 0..<80 {
            if viewModel.phase == .failed {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.phase == .failed)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.estimate == nil)
        #expect(viewModel.error != nil)
    }
}

private struct SlowGasPricingProvider: GasPricingProviding {
    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimate {
        try await Task.sleep(for: .seconds(5))
        return .example
    }
}

private struct FailingGasPricingProvider: GasPricingProviding {
    struct StubError: Error {}

    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimate {
        throw StubError()
    }
}
