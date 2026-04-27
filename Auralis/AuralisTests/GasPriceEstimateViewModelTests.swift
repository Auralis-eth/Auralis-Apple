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

    @Test("stale cache fetches preserve the live timestamp and mark the estimate as cached")
    func staleCacheFetchPreservesTimestampAndCachedState() async throws {
        let staleDate = Date(timeIntervalSince1970: 1_704_067_200)
        let viewModel = GasPriceEstimateViewModel(
            provider: StaleCachedGasPricingProvider(staleDate: staleDate)
        )

        viewModel.setChain(.ethMainnet)

        for _ in 0..<80 {
            if viewModel.phase == .loaded {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
        #expect(viewModel.estimate?.version == GasPriceEstimate.example.version)
        #expect(viewModel.estimate?.estimatedBaseFee == GasPriceEstimate.example.estimatedBaseFee)
        #expect(
            viewModel.estimate?.medium.suggestedMaxFeePerGas ==
                GasPriceEstimate.example.medium.suggestedMaxFeePerGas
        )
        #expect(viewModel.lastUpdated == staleDate)
        #expect(viewModel.isShowingCachedEstimate == true)
    }

    @Test("fresh cache hits are still labeled as cached instead of live")
    func freshCacheHitMarksEstimateAsCached() async throws {
        let cachedDate = Date(timeIntervalSince1970: 1_704_067_200)
        let viewModel = GasPriceEstimateViewModel(
            provider: FreshCachedGasPricingProvider(cachedDate: cachedDate)
        )

        viewModel.setChain(.ethMainnet)

        for _ in 0..<80 {
            if viewModel.phase == .loaded {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
        #expect(viewModel.lastUpdated == cachedDate)
        #expect(viewModel.isShowingCachedEstimate == true)
    }

    @Test("gas pricing auth failures are translated into actionable user-facing copy")
    func gasPricingUnauthorizedMessageIsActionable() {
        let error = AlchemyGasPricingProvider.GasPricingError.unauthorized(message: "invalid api key")
        #expect(
            error.userFacingMessage ==
                "Auralis could not refresh gas prices because the provider rejected this build's credentials."
        )
    }
}

private struct SlowGasPricingProvider: GasPricingProviding {
    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimateResult {
        try await Task.sleep(for: .seconds(5))
        return GasPriceEstimateResult(
            estimate: .example,
            fetchedAt: .now,
            source: .live
        )
    }
}

private struct FailingGasPricingProvider: GasPricingProviding {
    struct StubError: Error {}

    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimateResult {
        throw StubError()
    }
}

private struct StaleCachedGasPricingProvider: GasPricingProviding {
    let staleDate: Date

    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimateResult {
        GasPriceEstimateResult(
            estimate: .example,
            fetchedAt: staleDate,
            source: .staleCache
        )
    }
}

private struct FreshCachedGasPricingProvider: GasPricingProviding {
    let cachedDate: Date

    func gasPriceEstimate(for chain: Chain) async throws -> GasPriceEstimateResult {
        GasPriceEstimateResult(
            estimate: .example,
            fetchedAt: cachedDate,
            source: .cache
        )
    }
}
