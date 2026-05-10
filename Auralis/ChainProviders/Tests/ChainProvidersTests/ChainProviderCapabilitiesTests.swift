import AuralisPrimaryModels
import ChainProviders
import Testing

@Suite
struct ChainProviderCapabilitiesTests {
    @Test("Solana chains do not support EVM RPC")
    func solanaChainsDoNotSupportEVMRPC() {
        #expect(Chain.solanaMainnet.supportsEVMRPC == false)
        #expect(Chain.solanaDevnetTestnet.supportsEVMRPC == false)
    }

    @Test("Current non-Solana chains support EVM RPC")
    func nonSolanaChainsSupportEVMRPC() {
        for chain in Chain.allCases where !Self.solanaChains.contains(chain) {
            #expect(chain.supportsEVMRPC, "\(chain.rawValue) should explicitly support EVM RPC")
        }
    }

    @Test("Solana chains do not support ERC-20 holdings")
    func solanaChainsDoNotSupportERC20Holdings() {
        #expect(Chain.solanaMainnet.supportsERC20Holdings == false)
        #expect(Chain.solanaDevnetTestnet.supportsERC20Holdings == false)
    }

    @Test("Current non-Solana chains support ERC-20 holdings")
    func nonSolanaChainsSupportERC20Holdings() {
        for chain in Chain.allCases where !Self.solanaChains.contains(chain) {
            #expect(chain.supportsERC20Holdings, "\(chain.rawValue) should explicitly support ERC-20 holdings")
        }
    }

    private static let solanaChains: Set<Chain> = [
        .solanaMainnet,
        .solanaDevnetTestnet,
    ]
}
