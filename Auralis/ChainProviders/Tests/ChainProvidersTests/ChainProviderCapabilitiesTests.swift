import AuralisPrimaryModels
import AuralisTestSupport
import ChainProviders
import Foundation
import ProviderKit
import Testing

@Suite
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
        let session = URLSession.mocked { request in
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

        let expectedURL = URL(string: "https://example.test/rpc")!
        let factory = ReadOnlyChainProviderFactory(
            configurationResolver: StubProviderConfigurationResolver(rpcURL: expectedURL),
            session: session
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
