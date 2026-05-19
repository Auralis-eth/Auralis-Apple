import AuralisPrimaryModels
import ChainProviders
import Foundation
import NFTKit
import ProviderKit
import SwiftData
import TokenStorage

@MainActor
protocol ERC20HoldingsSyncing {
    func sync(request: ERC20HoldingsSyncRequest) async -> ERC20HoldingsSyncViewResult
}

struct ERC20HoldingsSyncRequest: Equatable {
    let accountAddress: String
    let chain: Chain
    let nativeBalanceDisplay: String?
    let nativeBalanceUpdatedAt: Date?
    let hadNoHoldings: Bool
}

struct ERC20HoldingsSyncViewResult: Equatable {
    let providerWarningMessage: String?
    let providerErrorMessage: String?
    let persistenceErrorMessage: String?
}

@MainActor
protocol ERC20HoldingsPersisting {
    func upsertNativeHolding(
        accountAddress: String,
        chain: Chain,
        amountDisplay: String,
        updatedAt: Date
    ) async throws

    func replaceERC20Holdings(
        accountAddress: String,
        chain: Chain,
        holdings: [ProviderTokenHolding]
    ) async throws
}

extension SwiftDataTokenHoldingsStore: ERC20HoldingsPersisting {}

@MainActor
final class LiveERC20HoldingsSyncUseCase: ERC20HoldingsSyncing {
    private let tokenHoldingsProviderFactory: () -> any TokenHoldingsProviding
    private let tokenHoldingsStoreFactory: @MainActor (ModelContext) -> any ERC20HoldingsPersisting
    private let modelContext: ModelContext
    private let syncCoordinator: ERC20HoldingsSyncCoordinator
    private let resultPresenter: ERC20HoldingsSyncResultPresenter

    init(
        tokenHoldingsProviderFactory: @escaping () -> any TokenHoldingsProviding,
        tokenHoldingsStoreFactory: @escaping @MainActor (ModelContext) -> any ERC20HoldingsPersisting,
        modelContext: ModelContext,
        syncCoordinator: ERC20HoldingsSyncCoordinator = ERC20HoldingsSyncCoordinator(),
        resultPresenter: ERC20HoldingsSyncResultPresenter = ERC20HoldingsSyncResultPresenter()
    ) {
        self.tokenHoldingsProviderFactory = tokenHoldingsProviderFactory
        self.tokenHoldingsStoreFactory = tokenHoldingsStoreFactory
        self.modelContext = modelContext
        self.syncCoordinator = syncCoordinator
        self.resultPresenter = resultPresenter
    }

    func sync(request: ERC20HoldingsSyncRequest) async -> ERC20HoldingsSyncViewResult {
        guard !request.accountAddress.isEmpty else {
            return ERC20HoldingsSyncViewResult(
                providerWarningMessage: nil,
                providerErrorMessage: nil,
                persistenceErrorMessage: nil
            )
        }

        let nativePersistenceErrorMessage = await syncNativeHoldingIfAvailable(request: request)

        guard request.chain.supportsERC20Holdings else {
            return ERC20HoldingsSyncViewResult(
                providerWarningMessage: nil,
                providerErrorMessage: nil,
                persistenceErrorMessage: nil
            )
        }

        let coordinatorRequest = ERC20HoldingsSyncCoordinator.Request(
            accountAddress: request.accountAddress,
            chain: request.chain
        )
        let coordinatorResult = await syncCoordinator.sync(
            request: coordinatorRequest,
            fetch: { [tokenHoldingsProviderFactory] request in
                try await tokenHoldingsProviderFactory().tokenHoldings(
                    for: request.accountAddress,
                    chain: request.chain
                )
            },
            persist: { [tokenHoldingsStoreFactory, modelContext] request, providerHoldings in
                try await tokenHoldingsStoreFactory(modelContext).replaceERC20Holdings(
                    accountAddress: request.accountAddress,
                    chain: request.chain,
                    holdings: providerHoldings
                )
            }
        )

        var viewResult = resultPresenter.present(
            coordinatorResult,
            hadNoHoldings: request.hadNoHoldings
        )

        if case .fetchFailed = coordinatorResult,
           let nativePersistenceErrorMessage {
            viewResult = ERC20HoldingsSyncViewResult(
                providerWarningMessage: viewResult.providerWarningMessage,
                providerErrorMessage: viewResult.providerErrorMessage,
                persistenceErrorMessage: nativePersistenceErrorMessage
            )
        }

        return viewResult
    }

    private func syncNativeHoldingIfAvailable(request: ERC20HoldingsSyncRequest) async -> String? {
        guard let nativeBalanceDisplay = request.nativeBalanceDisplay,
              let nativeBalanceUpdatedAt = request.nativeBalanceUpdatedAt else {
            return nil
        }

        do {
            try await tokenHoldingsStoreFactory(modelContext).upsertNativeHolding(
                accountAddress: request.accountAddress,
                chain: request.chain,
                amountDisplay: nativeBalanceDisplay,
                updatedAt: nativeBalanceUpdatedAt
            )
            return nil
        } catch {
            return "Auralis kept the last saved holdings view, but the latest native balance could not be written on this device."
        }
    }
}

struct ERC20HoldingsSyncResultPresenter {
    func present(
        _ result: ERC20HoldingsSyncCoordinator.Result,
        hadNoHoldings: Bool
    ) -> ERC20HoldingsSyncViewResult {
        switch result {
        case .applied(let warning):
            return ERC20HoldingsSyncViewResult(
                providerWarningMessage: warning?.message,
                providerErrorMessage: nil,
                persistenceErrorMessage: nil
            )
        case .fetchFailed(let error):
            return ERC20HoldingsSyncViewResult(
                providerWarningMessage: nil,
                providerErrorMessage: providerErrorMessage(for: error, hadNoHoldings: hadNoHoldings),
                persistenceErrorMessage: nil
            )
        case .persistFailed:
            return ERC20HoldingsSyncViewResult(
                providerWarningMessage: nil,
                providerErrorMessage: nil,
                persistenceErrorMessage: "Auralis kept the last saved ERC-20 holdings, but the refreshed token rows could not be written on this device."
            )
        case .dropped, .cancelled:
            return ERC20HoldingsSyncViewResult(
                providerWarningMessage: nil,
                providerErrorMessage: nil,
                persistenceErrorMessage: nil
            )
        }
    }

    func providerErrorMessage(
        for error: Error,
        hadNoHoldings: Bool
    ) -> String {
        if let providerError = error as? ProviderAbstractionError {
            switch providerError {
            case .unauthorized:
                return "Auralis could not refresh token holdings because the provider rejected this build's credentials for this request scope."
            case .rateLimited:
                return hadNoHoldings
                    ? "The token holdings provider is rate-limiting requests right now. Try again in a moment."
                    : "The token holdings provider is rate-limiting requests right now, so Auralis kept your last saved ERC-20 holdings."
            case .offline:
                return hadNoHoldings
                    ? "Auralis could not load token holdings because this device appears to be offline."
                    : "Auralis kept your last saved ERC-20 holdings because this device appears to be offline."
            case .unavailable:
                return hadNoHoldings
                    ? "Auralis could not load token holdings because the provider is temporarily unavailable for this wallet and chain."
                    : "Auralis kept your last saved ERC-20 holdings because the provider is temporarily unavailable for this wallet and chain."
            case .invalidResponse:
                return hadNoHoldings
                    ? "Auralis could not load token holdings because the provider returned data it could not read for this wallet and chain."
                    : "Auralis kept your last saved ERC-20 holdings because the provider returned data it could not read for this wallet and chain."
            case .badStatus(let statusCode, _):
                return hadNoHoldings
                    ? "Auralis could not load token holdings because the provider returned HTTP \(statusCode)."
                    : "Auralis kept your last saved ERC-20 holdings because the provider returned HTTP \(statusCode)."
            case .providerError:
                return hadNoHoldings
                    ? "Auralis could not load token holdings because the provider reported an error for this wallet and chain."
                    : "Auralis kept your last saved ERC-20 holdings because the provider reported an error for this wallet and chain."
            case .missingAPIKey:
                return "Auralis could not refresh token holdings because this build is missing provider configuration."
            case .unsupportedChain:
                return "Auralis cannot refresh token holdings for this chain yet."
            case .invalidURL:
                return "Auralis could not refresh token holdings because the provider configuration is invalid."
            case .invalidAddress:
                return "Auralis could not refresh token holdings because the active wallet address is invalid."
            case .invalidBalancePayload:
                return hadNoHoldings
                    ? "Auralis could not load token holdings because the provider returned an invalid balance payload."
                    : "Auralis kept your last saved ERC-20 holdings because the provider returned an invalid balance payload."
            case .paginationStalled:
                return hadNoHoldings
                    ? "Auralis could not load token holdings because the provider stopped paginating cleanly for this wallet and chain."
                    : "Auralis kept your last saved ERC-20 holdings because the provider stopped paginating cleanly for this wallet and chain."
            case .unsupportedMethod:
                return "Auralis could not refresh token holdings because the provider does not support the required method."
            }
        }

        return hadNoHoldings
            ? "Auralis could not load token holdings for the active wallet and chain just now. Try again in a moment."
            : "Auralis kept the last saved ERC-20 holdings because the live token provider did not respond cleanly for this scope."
    }
}
