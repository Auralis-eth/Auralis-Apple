@testable import Auralis
import AuralisPrimaryModels
import Foundation
import ProviderKit
import Testing

@Suite
@MainActor
struct GasPriceEstimateViewModelTests {
    @Test("setting the first chain immediately enters a non-error loading phase")
    func initialChainSelectionStartsInLoadingPhase() {
        let viewModel = GasPriceEstimateViewModel(provider: FailingGasPricingProvider())

        viewModel.setChain(.ethMainnet)

        #expect(viewModel.phase == .loading)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.error == nil)
        #expect(viewModel.estimate == nil)
    }

    @Test("failed fetches transition into the failed phase after the initial loading state", .timeLimit(.minutes(1)))
    func failedFetchTransitionsToFailedPhase() async throws {
        let viewModel = GasPriceEstimateViewModel(
            provider: FailingGasPricingProvider(),
            chainChangeDebounce: .zero
        )

        viewModel.setChain(.ethMainnet)

        #expect(viewModel.phase == .loading)

        await viewModel.waitForCurrentTask()

        #expect(viewModel.phase == .failed)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.estimate == nil)
        _ = try #require(viewModel.error as? FailingGasPricingProvider.StubError)
    }

    @Test("stale cache fetches preserve the live timestamp and mark the estimate as cached")
    func staleCacheFetchPreservesTimestampAndCachedState() async throws {
        let staleDate = Date(timeIntervalSince1970: 1_704_067_200)
        let viewModel = GasPriceEstimateViewModel(
            provider: StaleCachedGasPricingProvider(staleDate: staleDate),
            chainChangeDebounce: .zero
        )

        viewModel.setChain(.ethMainnet)

        await viewModel.waitForCurrentTask()

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
            provider: FreshCachedGasPricingProvider(cachedDate: cachedDate),
            chainChangeDebounce: .zero
        )

        viewModel.setChain(.ethMainnet)

        await viewModel.waitForCurrentTask()

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

    @Test("gas pricing public messages do not expose raw provider diagnostics")
    func gasPricingMessagesHideProviderDiagnostics() {
        let badStatus = AlchemyGasPricingProvider.GasPricingError.badStatus(
            400,
            message: #"{"message":"wallet=0x123 apiKey=secret"}"#
        )
        let rpcError = AlchemyGasPricingProvider.GasPricingError.rpcError(
            code: -32000,
            message: "debug url https://rpc.example/secret?apiKey=secret"
        )

        #expect(
            badStatus.userFacingMessage ==
                "Auralis could not load gas prices because the provider returned HTTP 400."
        )
        #expect(
            rpcError.userFacingMessage ==
                "Auralis could not load gas prices because the provider reported an error."
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
