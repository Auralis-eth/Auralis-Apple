@testable import Auralis
import Foundation
import Testing

@Suite
struct ENSResolutionServiceTests {
    @Test("forward resolution uses fresh cache before touching the client again")
    func forwardResolutionUsesFreshCache() async throws {
        let client = StubEthereumNameServiceClient()
        client.forwardResults["vitalik.eth"] = .success("0x1234567890abcdef1234567890abcdef12345678")

        let defaults = UserDefaults(suiteName: "ENSResolutionServiceTests.cache.\(UUID().uuidString)")!
        let cacheStore = ENSResolutionCacheStore(
            userDefaults: defaults,
            storageKey: "forwardResolutionUsesFreshCache"
        )
        let clock = MutableDateBox(Date(timeIntervalSince1970: 1_000))

        let resolver = Web3EthereumNameServiceResolver(
            client: client,
            cacheStore: cacheStore,
            freshnessTTL: 300,
            nowProvider: { clock.value }
        )

        let first = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "first")
        client.forwardResults["vitalik.eth"] = .failure(StubClientError.lookupFailed)
        clock.value = Date(timeIntervalSince1970: 1_100)
        let second = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "second")

        #expect(first.provenance == .network)
        #expect(second.provenance == .cache)
        #expect(first.address == second.address)
        #expect(client.forwardCallCount == 1)
    }

    @Test("forward resolution falls back to stale cache when refresh fails")
    func forwardResolutionFallsBackToStaleCache() async throws {
        let client = StubEthereumNameServiceClient()
        client.forwardResults["vitalik.eth"] = .success("0x1234567890abcdef1234567890abcdef12345678")

        let defaults = UserDefaults(suiteName: "ENSResolutionServiceTests.stale.\(UUID().uuidString)")!
        let cacheStore = ENSResolutionCacheStore(
            userDefaults: defaults,
            storageKey: "forwardResolutionFallsBackToStaleCache"
        )
        let clock = MutableDateBox(Date(timeIntervalSince1970: 1_000))

        let resolver = Web3EthereumNameServiceResolver(
            client: client,
            cacheStore: cacheStore,
            freshnessTTL: 60,
            nowProvider: { clock.value }
        )

        _ = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "first")
        client.forwardResults["vitalik.eth"] = .failure(StubClientError.lookupFailed)
        clock.value = Date(timeIntervalSince1970: 1_200)
        let stale = try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "second")

        #expect(stale.provenance == .staleCache)
        #expect(stale.isStale)
        #expect(stale.address == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(client.forwardCallCount == 2)
    }

    @Test("reverse lookup returns verified names only")
    func reverseLookupRequiresForwardVerification() async {
        let verifiedClient = StubEthereumNameServiceClient()
        verifiedClient.reverseResults["0x1234567890abcdef1234567890abcdef12345678"] = .success("vitalik.eth")
        verifiedClient.forwardResults["vitalik.eth"] = .success("0x1234567890abcdef1234567890abcdef12345678")

        let verifiedResolver = Web3EthereumNameServiceResolver(
            client: verifiedClient,
            cacheStore: ENSResolutionCacheStore(
                userDefaults: UserDefaults(suiteName: "ENSResolutionServiceTests.reverse.verified.\(UUID().uuidString)")!,
                storageKey: "verified"
            )
        )
        let verified = await verifiedResolver.reverseLookup(
            address: "0x1234567890abcdef1234567890abcdef12345678",
            correlationID: "verified"
        )

        #expect(verified?.ensName == "vitalik.eth")
        #expect(verified?.isForwardVerified == true)

        let mismatchedClient = StubEthereumNameServiceClient()
        mismatchedClient.reverseResults["0x1234567890abcdef1234567890abcdef12345678"] = .success("vitalik.eth")
        mismatchedClient.forwardResults["vitalik.eth"] = .success("0x9999999999999999999999999999999999999999")

        let mismatchedResolver = Web3EthereumNameServiceResolver(
            client: mismatchedClient,
            cacheStore: ENSResolutionCacheStore(
                userDefaults: UserDefaults(suiteName: "ENSResolutionServiceTests.reverse.mismatched.\(UUID().uuidString)")!,
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
        client.forwardResults["vitalik.eth"] = .success("0x1234567890abcdef1234567890abcdef12345678")

        let defaults = UserDefaults(suiteName: "ENSResolutionServiceTests.mapping.\(UUID().uuidString)")!
        let cacheStore = ENSResolutionCacheStore(
            userDefaults: defaults,
            storageKey: "forwardResolutionSurfacesMappingChanges"
        )
        let clock = MutableDateBox(Date(timeIntervalSince1970: 1_000))
        let resolver = Web3EthereumNameServiceResolver(
            client: client,
            cacheStore: cacheStore,
            freshnessTTL: 60,
            nowProvider: { clock.value }
        )

        _ = try? await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "initial")

        client.forwardResults["vitalik.eth"] = .success("0x9999999999999999999999999999999999999999")
        clock.value = Date(timeIntervalSince1970: 1_200)

        await #expect(throws: ENSResolutionError.mappingChanged(
            ensName: "vitalik.eth",
            cachedAddress: "0x1234567890abcdef1234567890abcdef12345678",
            resolvedAddress: "0x9999999999999999999999999999999999999999"
        )) {
            try await resolver.resolveAddress(forENS: "vitalik.eth", correlationID: "changed")
        }

        let cached = await resolver.cachedForwardResolution(forENS: "vitalik.eth")
        #expect(cached?.address == "0x1234567890abcdef1234567890abcdef12345678")
        #expect(cached?.isStale == true)
    }
}

private enum StubClientError: Error {
    case lookupFailed
}

private final class StubEthereumNameServiceClient: EthereumNameServiceClient {
    var forwardResults: [String: Result<String, Error>] = [:]
    var reverseResults: [String: Result<String, Error>] = [:]
    private(set) var forwardCallCount = 0
    private(set) var reverseCallCount = 0

    func resolveAddress(forENS name: String) async throws -> String {
        forwardCallCount += 1
        switch forwardResults[name, default: .failure(StubClientError.lookupFailed)] {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    func resolveName(forAddress address: String) async throws -> String {
        reverseCallCount += 1
        switch reverseResults[address, default: .failure(StubClientError.lookupFailed)] {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

private final class MutableDateBox: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}
