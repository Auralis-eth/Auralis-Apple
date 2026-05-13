import AuralisPrimaryModels
import ChainProviders
import Foundation
import ProviderKit
import Testing

@Suite(.serialized)
struct ChainProviderCapabilitiesTests {
    @Test("Every current chain has an explicit capability decision")
    func everyChainHasExplicitCapabilities() {
        let expectedChains = Set(Self.evmChains).union(Self.nonEVMChains)

        #expect(expectedChains == Set(Chain.allCases))
    }

    @Test("EVM RPC support is explicit", arguments: Self.evmChains)
    func evmChainsSupportEVMRPC(chain: Chain) {
        #expect(chain.supportsEVMRPC)
    }

    @Test("Non-EVM chains do not support EVM RPC", arguments: Self.nonEVMChains)
    func nonEVMChainsDoNotSupportEVMRPC(chain: Chain) {
        #expect(chain.supportsEVMRPC == false)
    }

    @Test("ERC-20 holding support is explicit", arguments: Self.evmChains)
    func evmChainsSupportERC20Holdings(chain: Chain) {
        #expect(chain.supportsERC20Holdings)
    }

    @Test("Non-EVM chains do not support ERC-20 holdings", arguments: Self.nonEVMChains)
    func nonEVMChainsDoNotSupportERC20Holdings(chain: Chain) {
        #expect(chain.supportsERC20Holdings == false)
    }

    @Test("Read-only factory injects native balance configuration and session")
    func readOnlyFactoryInjectsNativeBalanceDependencies() async throws {
        let requestedURL = LockedValue<URL?>(nil)
        StubURLProtocol.handler = { request in
            requestedURL.set(request.url)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(#"{"jsonrpc":"2.0","id":1,"result":"0x2a"}"#.utf8)
            return (response, data)
        }
        defer {
            StubURLProtocol.handler = nil
        }

        let expectedURL = URL(string: "https://example.test/rpc")!
        let factory = ReadOnlyChainProviderFactory(
            configurationResolver: StubProviderConfigurationResolver(rpcURL: expectedURL),
            session: makeStubSession()
        )

        let balance = try await factory.makeNativeBalanceProvider().nativeBalance(
            for: "0x0000000000000000000000000000000000000001",
            chain: .baseMainnet
        )

        #expect(balance == NativeBalance(weiHex: "0x2a", weiDecimal: "42"))
        #expect(requestedURL.value == expectedURL)
    }

    private static let evmChains: [Chain] = [
        .ethMainnet,
        .ethSepoliaTestnet,
        .baseMainnet,
        .baseSepoliaTestnet,
        .arbMainnet,
        .arbSepoliaTestnet,
        .arbNovaMainnet,
        .optMainnet,
        .optSepoliaTestnet,
        .polygonMainnet,
        .polygonAmoyTestnet,
        .worldchainMainnet,
        .worldchainSepoliaTestnet,
        .shapeMainnet,
        .shapeSepoliaTestnet,
        .inkMainnet,
        .inkSepoliaTestnet,
        .unichainMainnet,
        .unichainSepoliaTestnet,
        .soneiumMainnet,
        .soneiumMinatoTestnet,
        .berachainMainnet,
        .zoraMainnet,
        .zoraSepoliaTestnet,
        .polynomialMainnet,
        .polynomialSepoliaTestnet,
    ]

    private static let nonEVMChains: [Chain] = [
        .solanaMainnet,
        .solanaDevnetTestnet,
    ]

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct StubProviderConfigurationResolver: ProviderConfigurationResolving {
    let rpcURL: URL

    func configuration(for chain: Chain) throws -> ProviderEndpointConfiguration {
        ProviderEndpointConfiguration(
            chain: chain,
            alchemyNFTBaseURL: nil,
            alchemyDataAPIBaseURL: nil,
            alchemyRPCURL: rpcURL
        )
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ storage: Value) {
        self.storage = storage
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

private final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)

    nonisolated(unsafe) static var handler: Handler?

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
