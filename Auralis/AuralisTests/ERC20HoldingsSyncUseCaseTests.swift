@testable import Auralis
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit
import SwiftData
import Testing

@MainActor
@Suite
struct ERC20HoldingsSyncUseCaseTests {
    private let accountAddress = "0x1234567890abcdef1234567890abcdef12345678"

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PrimaryStoreSchema.schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeUseCase(
        provider: any TokenHoldingsProviding = RecordingTokenHoldingsProvider(),
        store: RecordingERC20HoldingsStore = RecordingERC20HoldingsStore()
    ) throws -> LiveERC20HoldingsSyncUseCase {
        LiveERC20HoldingsSyncUseCase(
            tokenHoldingsProviderFactory: { provider },
            tokenHoldingsStoreFactory: { _ in store },
            modelContext: try makeContext()
        )
    }

    @Test("successful provider fetch persists ERC-20 holdings and clears messages")
    func successfulProviderFetchPersistsERC20Holdings() async throws {
        let provider = RecordingTokenHoldingsProvider(result: .success(.init(holdings: [.sample], warning: nil)))
        let store = RecordingERC20HoldingsStore()
        let useCase = try makeUseCase(provider: provider, store: store)

        let result = await useCase.sync(request: request())

        #expect(result == ERC20HoldingsSyncViewResult(
            providerWarningMessage: nil,
            providerErrorMessage: nil,
            persistenceErrorMessage: nil
        ))
        #expect(await provider.requests == [ProviderRequest(accountAddress: accountAddress, chain: .ethMainnet)])
        #expect(store.events == [.replaceERC20(accountAddress: accountAddress, chain: .ethMainnet, holdings: [.sample])])
    }

    @Test("native balance sync persists before ERC-20 refresh")
    func nativeBalancePersistsBeforeERC20Refresh() async throws {
        let provider = RecordingTokenHoldingsProvider(result: .success(.init(holdings: [.sample], warning: nil)))
        let store = RecordingERC20HoldingsStore()
        let useCase = try makeUseCase(provider: provider, store: store)
        let updatedAt = Date(timeIntervalSince1970: 123)

        _ = await useCase.sync(request: request(nativeBalanceDisplay: "1.25 ETH", nativeBalanceUpdatedAt: updatedAt))

        #expect(store.events == [
            .upsertNative(accountAddress: accountAddress, chain: .ethMainnet, amountDisplay: "1.25 ETH", updatedAt: updatedAt),
            .replaceERC20(accountAddress: accountAddress, chain: .ethMainnet, holdings: [.sample])
        ])
    }

    @Test("empty account address is a no-op")
    func emptyAccountAddressSkipsProviderAndPersistence() async throws {
        let provider = RecordingTokenHoldingsProvider()
        let store = RecordingERC20HoldingsStore()
        let useCase = try makeUseCase(provider: provider, store: store)

        let result = await useCase.sync(request: request(accountAddress: "", nativeBalanceDisplay: "1.25 ETH", nativeBalanceUpdatedAt: .now))

        #expect(result == .empty)
        #expect(await provider.requests.isEmpty)
        #expect(store.events.isEmpty)
    }

    @Test("unsupported chain persists native balance but skips ERC-20 refresh")
    func unsupportedChainPersistsNativeBalanceAndSkipsERC20Refresh() async throws {
        let provider = RecordingTokenHoldingsProvider()
        let store = RecordingERC20HoldingsStore()
        let useCase = try makeUseCase(provider: provider, store: store)
        let updatedAt = Date(timeIntervalSince1970: 456)

        let result = await useCase.sync(request: request(chain: .solanaMainnet, nativeBalanceDisplay: "1 SOL", nativeBalanceUpdatedAt: updatedAt))

        #expect(result == .empty)
        #expect(await provider.requests.isEmpty)
        #expect(store.events == [
            .upsertNative(accountAddress: accountAddress, chain: .solanaMainnet, amountDisplay: "1 SOL", updatedAt: updatedAt)
        ])
    }

    @Test("a newer use-case sync drops stale persistence from an older sync")
    func newerUseCaseSyncDropsStalePersistenceFromOlderSync() async throws {
        let provider = SequencedTokenHoldingsProvider()
        let store = RecordingERC20HoldingsStore()
        let useCase = try makeUseCase(provider: provider, store: store)
        let firstFetchStarted = AsyncSignal()
        let releaseFirstFetch = AsyncSignal()
        let firstHolding = ProviderTokenHolding.makeSample(symbol: "OLD", amountDisplay: "1 OLD")
        let secondHolding = ProviderTokenHolding.makeSample(symbol: "NEW", amountDisplay: "2 NEW")

        await provider.enqueue { _, _ in
            await firstFetchStarted.signal()
            await releaseFirstFetch.wait()
            return TokenHoldingsFetchResult(holdings: [firstHolding], warning: nil)
        }
        await provider.enqueue { _, _ in
            TokenHoldingsFetchResult(holdings: [secondHolding], warning: nil)
        }

        let firstTask = Task {
            await useCase.sync(request: request(accountAddress: "0x1111111111111111111111111111111111111111"))
        }

        await firstFetchStarted.wait()

        let secondResult = await useCase.sync(request: request(accountAddress: "0x2222222222222222222222222222222222222222"))

        await releaseFirstFetch.signal()
        let firstResult = await firstTask.value

        #expect(secondResult == .empty)
        #expect(firstResult == .empty)
        #expect(store.events == [
            .replaceERC20(
                accountAddress: "0x2222222222222222222222222222222222222222",
                chain: .ethMainnet,
                holdings: [secondHolding]
            )
        ])
    }

    @Test("provider warning is returned without failing the sync")
    func providerWarningReturnsWarningMessage() async throws {
        let warning = TokenHoldingsProviderWarning(message: "Some token metadata is delayed.")
        let provider = RecordingTokenHoldingsProvider(result: .success(.init(holdings: [.sample], warning: warning)))
        let useCase = try makeUseCase(provider: provider)

        let result = await useCase.sync(request: request())

        #expect(result.providerWarningMessage == warning.message)
        #expect(result.providerErrorMessage == nil)
        #expect(result.persistenceErrorMessage == nil)
    }

    @Test("provider failures map to existing user-facing messages")
    func providerFailuresMapToExistingMessages() {
        let presenter = ERC20HoldingsSyncResultPresenter()
        let cases: [(ProviderAbstractionError, Bool, String)] = [
            (.unauthorized, true, "Auralis could not refresh token holdings because the provider rejected this build's credentials for this request scope."),
            (.rateLimited, true, "The token holdings provider is rate-limiting requests right now. Try again in a moment."),
            (.offline, false, "Auralis kept your last saved ERC-20 holdings because this device appears to be offline."),
            (.unavailable, true, "Auralis could not load token holdings because the provider is temporarily unavailable for this wallet and chain."),
            (.invalidResponse, false, "Auralis kept your last saved ERC-20 holdings because the provider returned data it could not read for this wallet and chain."),
            (.badStatus(503, message: "backend detail"), true, "Auralis could not load token holdings because the provider returned HTTP 503."),
            (.providerError("raw rpc detail"), false, "Auralis kept your last saved ERC-20 holdings because the provider reported an error for this wallet and chain."),
            (.missingAPIKey(.alchemy), true, "Auralis could not refresh token holdings because this build is missing provider configuration."),
            (.unsupportedChain(.solanaMainnet), true, "Auralis cannot refresh token holdings for this chain yet."),
            (.invalidURL, true, "Auralis could not refresh token holdings because the provider configuration is invalid."),
            (.invalidAddress, true, "Auralis could not refresh token holdings because the active wallet address is invalid."),
            (.invalidBalancePayload, true, "Auralis could not load token holdings because the provider returned an invalid balance payload."),
            (.paginationStalled, false, "Auralis kept your last saved ERC-20 holdings because the provider stopped paginating cleanly for this wallet and chain."),
            (.unsupportedMethod, true, "Auralis could not refresh token holdings because the provider does not support the required method.")
        ]

        for (error, hadNoHoldings, expectedMessage) in cases {
            let result = presenter.present(.fetchFailed(error), hadNoHoldings: hadNoHoldings)
            #expect(result.providerErrorMessage == expectedMessage)
            #expect(result.providerWarningMessage == nil)
            #expect(result.persistenceErrorMessage == nil)
        }
    }

    @Test("persistence failure maps to the existing local-storage message")
    func persistenceFailureMapsToLocalStorageMessage() async throws {
        let provider = RecordingTokenHoldingsProvider(result: .success(.init(holdings: [.sample], warning: nil)))
        let store = RecordingERC20HoldingsStore(replaceError: TestError.persistence)
        let useCase = try makeUseCase(provider: provider, store: store)

        let result = await useCase.sync(request: request())

        #expect(result.providerWarningMessage == nil)
        #expect(result.providerErrorMessage == nil)
        #expect(result.persistenceErrorMessage == "Auralis kept the last saved ERC-20 holdings, but the refreshed token rows could not be written on this device.")
    }

    @Test("native persistence failure survives provider failure like the previous view flow")
    func nativePersistenceFailureSurvivesProviderFailure() async throws {
        let provider = RecordingTokenHoldingsProvider(result: .failure(ProviderAbstractionError.offline))
        let store = RecordingERC20HoldingsStore(nativeError: TestError.persistence)
        let useCase = try makeUseCase(provider: provider, store: store)

        let result = await useCase.sync(request: request(nativeBalanceDisplay: "1.25 ETH", nativeBalanceUpdatedAt: .now))

        #expect(result.providerErrorMessage == "Auralis could not load token holdings because this device appears to be offline.")
        #expect(result.persistenceErrorMessage == "Auralis kept the last saved holdings view, but the latest native balance could not be written on this device.")
    }

    @Test("dropped and cancelled coordinator results are no-op view results")
    func droppedAndCancelledCoordinatorResultsDoNotProduceMessages() {
        let presenter = ERC20HoldingsSyncResultPresenter()

        #expect(presenter.present(.dropped, hadNoHoldings: true) == .empty)
        #expect(presenter.present(.cancelled, hadNoHoldings: false) == .empty)
    }

    @Test("ERC-20 view does not own provider fetch or token persistence orchestration")
    func erc20ViewDoesNotRegressIntoProviderOrPersistenceOrchestration() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Auralis/Aura/MainTabERC20Views.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(!source.contains("tokenHoldingsProviderFactory().tokenHoldings"))
        #expect(!source.contains("replaceERC20Holdings("))
        #expect(!source.contains("holdingsSyncerFactory(modelContext).sync"))
        #expect(source.contains("currentHoldingsSyncer().sync"))
    }

    private func request(
        accountAddress: String? = nil,
        chain: Chain = .ethMainnet,
        nativeBalanceDisplay: String? = nil,
        nativeBalanceUpdatedAt: Date? = nil,
        hadNoHoldings: Bool = true
    ) -> ERC20HoldingsSyncRequest {
        ERC20HoldingsSyncRequest(
            accountAddress: accountAddress ?? self.accountAddress,
            chain: chain,
            nativeBalanceDisplay: nativeBalanceDisplay,
            nativeBalanceUpdatedAt: nativeBalanceUpdatedAt,
            hadNoHoldings: hadNoHoldings
        )
    }
}

private extension ERC20HoldingsSyncViewResult {
    static let empty = ERC20HoldingsSyncViewResult(
        providerWarningMessage: nil,
        providerErrorMessage: nil,
        persistenceErrorMessage: nil
    )
}

private struct ProviderRequest: Equatable {
    let accountAddress: String
    let chain: Chain
}

private actor RecordingTokenHoldingsProvider: TokenHoldingsProviding {
    enum Result {
        case success(TokenHoldingsFetchResult)
        case failure(Error)
    }

    private(set) var requests: [ProviderRequest] = []
    private var result: Result

    init(result: Result = .success(.init(holdings: [], warning: nil))) {
        self.result = result
    }

    func tokenHoldings(for address: String, chain: Chain) async throws -> TokenHoldingsFetchResult {
        requests.append(ProviderRequest(accountAddress: address, chain: chain))
        switch result {
        case .success(let fetchResult):
            return fetchResult
        case .failure(let error):
            throw error
        }
    }
}

private actor SequencedTokenHoldingsProvider: TokenHoldingsProviding {
    typealias Response = @Sendable (String, Chain) async throws -> TokenHoldingsFetchResult

    private var responses: [Response] = []

    func enqueue(_ response: @escaping Response) {
        responses.append(response)
    }

    func tokenHoldings(for address: String, chain: Chain) async throws -> TokenHoldingsFetchResult {
        let response = responses.removeFirst()
        return try await response(address, chain)
    }
}

private actor AsyncSignal {
    private var hasSignaled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if hasSignaled {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func signal() {
        hasSignaled = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

@MainActor
private final class RecordingERC20HoldingsStore: ERC20HoldingsPersisting {
    enum Event: Equatable {
        case upsertNative(accountAddress: String, chain: Chain, amountDisplay: String, updatedAt: Date)
        case replaceERC20(accountAddress: String, chain: Chain, holdings: [ProviderTokenHolding])
    }

    private(set) var events: [Event] = []
    private let nativeError: Error?
    private let replaceError: Error?

    init(nativeError: Error? = nil, replaceError: Error? = nil) {
        self.nativeError = nativeError
        self.replaceError = replaceError
    }

    func upsertNativeHolding(
        accountAddress: String,
        chain: Chain,
        amountDisplay: String,
        updatedAt: Date
    ) async throws {
        if let nativeError {
            throw nativeError
        }
        events.append(.upsertNative(
            accountAddress: accountAddress,
            chain: chain,
            amountDisplay: amountDisplay,
            updatedAt: updatedAt
        ))
    }

    func replaceERC20Holdings(
        accountAddress: String,
        chain: Chain,
        holdings: [ProviderTokenHolding]
    ) async throws {
        if let replaceError {
            throw replaceError
        }
        events.append(.replaceERC20(
            accountAddress: accountAddress,
            chain: chain,
            holdings: holdings
        ))
    }
}

private enum TestError: Error {
    case persistence
}

private extension ProviderTokenHolding {
    static let sample = makeSample()

    static func makeSample(
        symbol: String = "TOK",
        amountDisplay: String = "42.00"
    ) -> ProviderTokenHolding {
        ProviderTokenHolding(
            contractAddress: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
            symbol: symbol,
            displayName: "Token",
            amountDisplay: amountDisplay,
            updatedAt: Date(timeIntervalSince1970: 100),
            isPlaceholder: false,
            isAmountHidden: false
        )
    }
}
