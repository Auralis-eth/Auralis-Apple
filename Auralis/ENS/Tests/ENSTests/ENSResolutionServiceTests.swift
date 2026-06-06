import AuralisPrimaryModels
import AuralisTestSupport
import ENS
import Foundation
import ProviderKit
import Testing

struct ENSResolutionServiceTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTestDate(
        offsetFromNow: TimeInterval = 0
    ) -> Date {
        referenceDate.addingTimeInterval(offsetFromNow)
    }

    @Test("live ENS client preserves missing provider configuration instead of flattening it to provider unavailable")
    @MainActor
    func liveClientSurfacesMissingProviderConfiguration() async {
        let resolver = StubProviderConfigurationResolver(configuration: ProviderEndpointConfiguration(
            chain: .ethMainnet,
            alchemyNFTBaseURL: nil,
            alchemyDataAPIBaseURL: nil,
            alchemyRPCURL: nil
        ))

        let client = ENSResolvers.makeLiveClient(
            configurationResolver: ProviderBackedENSConfigurationResolver(
                configurationResolver: resolver
            )
        )

        await #expect(throws: ENSResolutionError.missingProviderConfiguration) {
            _ = try await client.resolveAddress(forENS: "vitalik.eth")
        }
    }

    @Test("live ENS client preserves invalid provider configuration distinctly")
    @MainActor
    func liveClientSurfacesInvalidProviderConfiguration() async {
        let client = ENSResolvers.makeLiveClient(
            configurationResolver: ProviderBackedENSConfigurationResolver(
                configurationResolver: StubProviderConfigurationResolver(error: ProviderAbstractionError.invalidURL)
            )
        )

        await #expect(throws: ENSResolutionError.invalidProviderConfiguration) {
            _ = try await client.resolveAddress(forENS: "vitalik.eth")
        }
    }

    @Test("forward resolution uses fresh cache before touching the client again")
    func forwardResolutionUsesFreshCache() async throws {
        let client = StubEthereumNameServiceClient()
        await client.setForwardResult(
            .success("0x1234567890abcdef1234567890abcdef12345678"),
            for: "vitalik.eth"
        )

        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ENSResolutionServiceTests.cache")
        defer { cleanup() }
        let clock = MutableDateBox(makeTestDate())
        let cacheStore = ENSResolutionCacheStore(
            userDefaultsStore: ENSCacheUserDefaults(defaults),
            storageKey: "forwardResolutionUsesFreshCache",
            retentionTTL: 60 * 60 * 24,
            nowProvider: { clock.value }
        )

        let resolver = Web3EthereumNameServiceResolver(
            client: client,
            cacheStore: cacheStore,
            freshnessTTL: 300,
            nowProvider: { clock.value }
        )

        let first = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "first")
        await client.setForwardResult(.failure(StubClientError.lookupFailed), for: "vitalik.eth")
        clock.value = makeTestDate(offsetFromNow: 100)
        let second = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "second")

        #expect(first.provenance == .network)
        #expect(second.provenance == .cache)
        #expect(first.address == second.address)
        #expect(await client.forwardCallCount() == 1)
    }

    @Test("forward resolution falls back to stale cache when refresh fails")
    func forwardResolutionFallsBackToStaleCache() async throws {
        let client = StubEthereumNameServiceClient()
        await client.setForwardResult(
            .success("0x1234567890abcdef1234567890abcdef12345678"),
            for: "vitalik.eth"
        )

        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ENSResolutionServiceTests.stale")
        defer { cleanup() }
        let clock = MutableDateBox(makeTestDate())
        let cacheStore = ENSResolutionCacheStore(
            userDefaultsStore: ENSCacheUserDefaults(defaults),
            storageKey: "forwardResolutionFallsBackToStaleCache",
            retentionTTL: 60 * 60 * 24,
            nowProvider: { clock.value }
        )

        let resolver = Web3EthereumNameServiceResolver(
            client: client,
            cacheStore: cacheStore,
            freshnessTTL: 60,
            nowProvider: { clock.value }
        )

        _ = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "first")
        await client.setForwardResult(.failure(StubClientError.lookupFailed), for: "vitalik.eth")
        clock.value = makeTestDate(offsetFromNow: 200)
        let stale = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "second")

        #expect(stale.provenance == .staleCache)
        #expect(stale.isStale)
        #expect(stale.address == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(await client.forwardCallCount() == 2)
    }

    @Test("reverse lookup returns verified names only")
    func reverseLookupRequiresForwardVerification() async throws {
        let verifiedClient = StubEthereumNameServiceClient()
        await verifiedClient.setReverseResult(
            .success("vitalik.eth"),
            for: "0x1234567890abcdef1234567890abcdef12345678"
        )
        await verifiedClient.setForwardResult(
            .success("0x1234567890abcdef1234567890abcdef12345678"),
            for: "vitalik.eth"
        )
        let (verifiedDefaults, verifiedCleanup) = try TestSupport.temporaryUserDefaults(
            prefix: "ENSResolutionServiceTests.reverse.verified"
        )
        defer { verifiedCleanup() }

        let verifiedResolver = Web3EthereumNameServiceResolver(
            client: verifiedClient,
            cacheStore: ENSResolutionCacheStore(
                userDefaultsStore: ENSCacheUserDefaults(verifiedDefaults),
                storageKey: "verified"
            )
        )
        let verified = await verifiedResolver.reverseLookup(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            correlationID: "verified"
        )

        let verified = try #require(verified)
        #expect(verified.ensName == "vitalik.eth")
        #expect(verified.isForwardVerified)

        let mismatchedClient = StubEthereumNameServiceClient()
        await mismatchedClient.setReverseResult(
            .success("vitalik.eth"),
            for: "0x1234567890abcdef1234567890abcdef12345678"
        )
        await mismatchedClient.setForwardResult(
            .success("0x9999999999999999999999999999999999999999"),
            for: "vitalik.eth"
        )
        let (mismatchedDefaults, mismatchedCleanup) = try TestSupport.temporaryUserDefaults(
            prefix: "ENSResolutionServiceTests.reverse.mismatched"
        )
        defer { mismatchedCleanup() }

        let mismatchedResolver = Web3EthereumNameServiceResolver(
            client: mismatchedClient,
            cacheStore: ENSResolutionCacheStore(
                userDefaultsStore: ENSCacheUserDefaults(mismatchedDefaults),
                storageKey: "mismatched"
            )
        )
        let mismatched = await mismatchedResolver.reverseLookup(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            correlationID: "mismatched"
        )

        #expect(mismatched == nil)
    }

    @Test("forward resolution refuses to silently overwrite a changed cached mapping")
    func forwardResolutionSurfacesMappingChanges() async {
        let client = StubEthereumNameServiceClient()
        await client.setForwardResult(
            .success("0x1234567890abcdef1234567890abcdef12345678"),
            for: "vitalik.eth"
        )

        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(prefix: "ENSResolutionServiceTests.mapping")
        defer { cleanup() }
        let clock = MutableDateBox(makeTestDate())
        let cacheStore = ENSResolutionCacheStore(
            userDefaultsStore: ENSCacheUserDefaults(defaults),
            storageKey: "forwardResolutionSurfacesMappingChanges",
            retentionTTL: 60 * 60 * 24,
            nowProvider: { clock.value }
        )
        let resolver = Web3EthereumNameServiceResolver(
            client: client,
            cacheStore: cacheStore,
            freshnessTTL: 60,
            nowProvider: { clock.value }
        )

        _ = try? await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "initial")

        await client.setForwardResult(
            .success("0x9999999999999999999999999999999999999999"),
            for: "vitalik.eth"
        )
        clock.value = makeTestDate(offsetFromNow: 200)

        await #expect(throws: ENSResolutionError.mappingChanged(
            ensName: "vitalik.eth",
            cachedAddress: "0x1234567890abcdef1234567890abcdef12345678",
            resolvedAddress: "0x9999999999999999999999999999999999999999"
        )) {
            try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "changed")
        }

        let cached = await resolver.cachedForwardResolution(forENS: "vitalik.eth")
        #expect(cached == nil)
    }

    @Test("forward resolution surfaces offchain-enabled network provenance explicitly")
    func forwardResolutionMarksOffchainEnabledNetworkLookups() async throws {
        let client = StubEthereumNameServiceClient(allowsOffchainLookup: true)
        await client.setForwardResult(
            .success("0x1234567890abcdef1234567890abcdef12345678"),
            for: "vitalik.eth"
        )

        let (offchainDefaults, offchainCleanup) = try TestSupport.temporaryUserDefaults(
            prefix: "ENSResolutionServiceTests.offchain"
        )
        defer { offchainCleanup() }
        let resolver = Web3EthereumNameServiceResolver(
            client: client,
            cacheStore: ENSResolutionCacheStore(
                userDefaultsStore: ENSCacheUserDefaults(offchainDefaults),
                storageKey: "offchain",
                retentionTTL: 60 * 60 * 24
            )
        )
        let resolution = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "offchain")

        #expect(resolution.provenance == .networkOffchainLookupAllowed)
    }

    @Test("live ENS resolver and cache reset service share one cache store instance")
    @MainActor
    func liveResolverAndResetServiceShareCacheStore() async throws {
        let (defaults, cleanup) = try TestSupport.temporaryUserDefaults(
            prefix: "ENSResolutionServiceTests.shared-reset"
        )
        defer { cleanup() }
        let clock = MutableDateBox(makeTestDate())
        let cacheStore = ENSResolutionCacheStore(
            userDefaultsStore: ENSCacheUserDefaults(defaults),
            storageKey: "shared-reset",
            nowProvider: { clock.value }
        )

        let resolver = ENSResolvers.live(
            configurationResolver: ProviderBackedENSConfigurationResolver(
                configurationResolver: StubProviderConfigurationResolver(error: ProviderAbstractionError.invalidURL)
            ),
            cacheStore: cacheStore
        )
        let resetService = ENSResolvers.cacheResetService(cacheStore: cacheStore)

        await cacheStore.storeForwardResolution(
            ENSForwardCacheEntry(
                ensName: "vitalik.eth",
                address: "0x1234567890abcdef1234567890abcdef12345678",
                fetchedAt: makeTestDate()
            )
        )

        let cachedBeforeReset = await resolver.cachedForwardResolution(forENS: "vitalik.eth")
        #expect(try #require(cachedBeforeReset).address == "0x1234567890abcdef1234567890abcdef12345678")

        await resetService.resetCache()

        let cachedAfterReset = await resolver.cachedForwardResolution(forENS: "vitalik.eth")
        #expect(cachedAfterReset == nil)
    }
}

private enum StubClientError: Error {
    case lookupFailed
}

private actor StubEthereumNameServiceClient: EthereumNameServiceClient {
    let allowsOffchainLookup: Bool
    private var forwardResults: [String: Result<String, Error>] = [:]
    private var reverseResults: [String: Result<String, Error>] = [:]
    private var forwardCallCountValue = 0
    private var reverseCallCountValue = 0

    init(allowsOffchainLookup: Bool = false) {
        self.allowsOffchainLookup = allowsOffchainLookup
    }

    func resolveAddress(forENS name: String) async throws -> String {
        forwardCallCountValue += 1
        switch forwardResults[name, default: .failure(StubClientError.lookupFailed)] {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    func resolveName(forAddress address: String) async throws -> String {
        reverseCallCountValue += 1
        switch reverseResults[address, default: .failure(StubClientError.lookupFailed)] {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    func setForwardResult(_ result: Result<String, Error>, for name: String) {
        forwardResults[name] = result
    }

    func setReverseResult(_ result: Result<String, Error>, for address: String) {
        reverseResults[address] = result
    }

    func forwardCallCount() -> Int {
        forwardCallCountValue
    }

    func reverseCallCount() -> Int {
        reverseCallCountValue
    }
}

private struct StubProviderConfigurationResolver: ProviderConfigurationResolving {
    let configuration: ProviderEndpointConfiguration?
    let error: Error?

    init(
        configuration: ProviderEndpointConfiguration? = nil,
        error: Error? = nil
    ) {
        self.configuration = configuration
        self.error = error
    }

    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration {
        if let error {
            throw error
        }

        guard let configuration else {
            throw ProviderAbstractionError.invalidURL
        }

        return configuration
    }
}

// Synchronous `nowProvider: () -> Date` seam used to drive deterministic time
// in tests. Cannot be an actor without forcing the provider to become async.
private final class MutableDateBox: Sendable {
    nonisolated(unsafe) var value: Date

    init(_ value: Date) {
        self.value = value
    }
}
