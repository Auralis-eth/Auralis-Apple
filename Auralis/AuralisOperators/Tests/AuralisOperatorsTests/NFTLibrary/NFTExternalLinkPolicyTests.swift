import AuralisCrypto
import Foundation
@testable import AuralisOperators
import Testing

/// The two external-link buttons in this feature each validate against a policy narrowed to the one
/// route type their URL builder can produce, so the authority a button carries matches what it is
/// for. These tests hold both halves of that: the narrowing is real, and it did not blocklist any
/// route the buttons actually build.
struct NFTExternalLinkPolicyTests {
    @Test("the marketplace button approves OpenSea and nothing else on the built-in allowlist")
    func marketplacePolicyIsNarrowedToOpenSea() throws {
        let policy = NFTExternalLinkPolicies.marketplace
        let openSea = try #require(URL(string: "https://opensea.io/assets/ethereum/0x0000000000000000000000000000000000000abc/1"))

        guard case .success = policy.validate(.init(label: "OpenSea", url: openSea)) else {
            Issue.record("Expected the OpenSea route to stay approved.")
            return
        }

        // Also proves the policy did not fall into its fail-closed branch, which would block the
        // line above rather than only these.
        for blocked in ["https://etherscan.io/token/0xabc", "https://ipfs.io/ipfs/QmHash", "https://arweave.net/tx/abc"] {
            let url = try #require(URL(string: blocked))
            #expect(
                policy.validate(.init(label: "Off-route", url: url)).isSuccess == false,
                "\(blocked) is not a marketplace route and the marketplace button should not carry authority for it."
            )
        }
    }

    @Test("the explorer button approves explorer routes and not marketplace or gateway ones")
    func explorerPolicyIsNarrowedToExplorers() throws {
        let policy = NFTExternalLinkPolicies.explorer
        let explorer = try #require(URL(string: "https://etherscan.io/token/0x0000000000000000000000000000000000000abc"))

        guard case .success = policy.validate(.init(label: "Etherscan", url: explorer)) else {
            Issue.record("Expected the explorer route to stay approved.")
            return
        }

        for blocked in ["https://opensea.io/assets/ethereum/0xabc/1", "https://ipfs.io/ipfs/QmHash"] {
            let url = try #require(URL(string: blocked))
            #expect(
                policy.validate(.init(label: "Off-route", url: url)).isSuccess == false,
                "\(blocked) is not an explorer route and the explorer button should not carry authority for it."
            )
        }
    }

    @Test("every chain the explorer builder supports survives the narrowed policy")
    func explorerPolicyApprovesEveryBuildableChain() throws {
        // The regression this narrowing could plausibly cause: a chain whose explorer host is in the
        // catalog but not in the policy's explorer rules would go from opening to blocked. Walking
        // every chain is the only way to see that, since the host varies per chain.
        let builder = ExplorerURLBuilder()
        let policy = NFTExternalLinkPolicies.explorer
        let contract = "0x0000000000000000000000000000000000000abc"

        for chain in Chain.allCases {
            guard let url = try? builder.url(for: .nft(contract: contract, tokenID: "1", chain: chain)) else {
                continue
            }

            #expect(
                policy.validate(.init(label: "Explorer", url: url)).isSuccess,
                "\(chain.rawValue) builds \(url.absoluteString), which the narrowed explorer policy blocks."
            )
        }
    }

    @Test("every chain the OpenSea builder supports survives the narrowed policy")
    func marketplacePolicyApprovesEveryBuildableChain() throws {
        let builder = OpenSeaDestinationBuilder()
        let policy = NFTExternalLinkPolicies.marketplace
        let contract = "0x0000000000000000000000000000000000000abc"

        for chain in Chain.allCases {
            guard let url = try? builder.url(contract: contract, tokenID: "1", chain: chain) else {
                continue
            }

            #expect(
                policy.validate(.init(label: "OpenSea", url: url)).isSuccess,
                "\(chain.rawValue) builds \(url.absoluteString), which the narrowed marketplace policy blocks."
            )
        }
    }
}

private extension Result where Success == ExternalLinkConfirmationDestination, Failure == ExternalLinkValidationFailure {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
