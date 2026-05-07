@testable import Auralis
import AuralisPrimaryModels
import Foundation
import Testing

@Suite
struct ExternalLinkDestinationTests {
    @Test("OpenSea URLs are chain aware and unsupported chains stay hidden")
    func openSeaURLsFollowChainSupport() {
        let baseURL = Chain.baseMainnet.openSeaURL(contractAddress: "0xabc", tokenId: "1")
        #expect(baseURL?.absoluteString == "https://opensea.io/assets/base/0xabc/1")

        let unsupportedURL = Chain.baseSepoliaTestnet.openSeaURL(contractAddress: "0xabc", tokenId: "1")
        #expect(unsupportedURL == nil)
    }

    @Test("Explorer URLs use the chain-specific scanner host")
    func explorerURLsFollowChain() {
        let baseURL = Chain.baseMainnet.nftExplorerURL(contractAddress: "0xabc", tokenId: "1")
        #expect(baseURL?.absoluteString == "https://basescan.org/token/0xabc?a=1")

        let arbitrumLabel = Chain.arbMainnet.nftExplorerDestination?.label
        #expect(arbitrumLabel == "Arbiscan")
    }

    @Test("external link policy accepts every supported explorer host")
    func policyAcceptsAllSupportedExplorerHosts() {
        let policy = ExternalLinkPolicy()
        let explorerCandidates: [(String, Chain)] = [
            ("Etherscan", .ethMainnet),
            ("Etherscan", .ethSepoliaTestnet),
            ("BaseScan", .baseMainnet),
            ("BaseScan", .baseSepoliaTestnet),
            ("Arbiscan", .arbMainnet),
            ("Arbiscan", .arbSepoliaTestnet),
            ("Arbiscan", .arbNovaMainnet),
            ("Optimistic Etherscan", .optMainnet),
            ("Optimistic Etherscan", .optSepoliaTestnet),
            ("PolygonScan", .polygonMainnet),
            ("PolygonScan", .polygonAmoyTestnet)
        ]

        for (label, chain) in explorerCandidates {
            guard let url = chain.nftExplorerURL(contractAddress: "0xabc", tokenId: "1") else {
                Issue.record("Expected explorer URL for \(chain.rawValue)")
                continue
            }

            let candidate = ExternalLinkCandidateDestination(label: label, url: url)
            guard case .success(let destination) = policy.validate(candidate) else {
                Issue.record("Expected supported explorer host to validate: \(url.absoluteString)")
                continue
            }

            #expect(destination.label == label)
            #expect(destination.hostDisplay == url.host())
        }
    }

    @Test("external link policy accepts approved marketplace IPFS and Arweave hosts")
    func policyAcceptsApprovedHosts() {
        let policy = ExternalLinkPolicy()

        let approvedCandidates = [
            ExternalLinkCandidateDestination(label: "OpenSea", url: URL(string: "https://opensea.io/assets/base/0xabc/1")!),
            ExternalLinkCandidateDestination(label: "IPFS", url: URL(string: "https://ipfs.io/ipfs/QmHash")!),
            ExternalLinkCandidateDestination(label: "IPFS", url: URL(string: "https://cloudflare-ipfs.com/ipfs/QmHash")!),
            ExternalLinkCandidateDestination(label: "IPFS", url: URL(string: "https://gateway.pinata.cloud/ipfs/QmHash")!),
            ExternalLinkCandidateDestination(label: "Arweave", url: URL(string: "https://arweave.net/tx/example")!)
        ]

        for candidate in approvedCandidates {
            guard case .success(let destination) = policy.validate(candidate) else {
                Issue.record("Expected approved host to validate: \(candidate.url.absoluteString)")
                continue
            }

            #expect(destination.label == candidate.label)
            #expect(destination.hostDisplay == candidate.url.host())
        }
    }

    @Test("external link policy rejects unsupported and suspicious destinations with typed failures")
    func policyRejectsBlockedDestinations() {
        let policy = ExternalLinkPolicy()

        let unsupportedHost = ExternalLinkCandidateDestination(label: "Bad", url: URL(string: "https://example.com/phish")!)
        let missingHost = ExternalLinkCandidateDestination(label: "Broken", url: URL(string: "https:///missing-host")!)
        let badSchemes = [
            "javascript:alert(1)",
            "file:///tmp/test",
            "data:text/plain,hello",
            "auralis://wallet"
        ]

        #expect(policy.validate(unsupportedHost) == .failure(.unsupportedHost("example.com")))
        #expect(policy.validate(missingHost) == .failure(.missingHost))

        for rawValue in badSchemes {
            let candidate = ExternalLinkCandidateDestination(label: "Blocked", url: URL(string: rawValue)!)
            guard case .failure(.invalidScheme) = policy.validate(candidate) else {
                Issue.record("Expected invalid scheme failure for \(rawValue)")
                continue
            }
        }
    }

    @Test("external link policy preserves user-visible host and path displays")
    func policyBuildsDisplayFields() {
        let policy = ExternalLinkPolicy()

        let emptyPath = ExternalLinkCandidateDestination(label: "Explorer", url: URL(string: "https://etherscan.io")!)
        let tokenPath = ExternalLinkCandidateDestination(label: "OpenSea", url: URL(string: "https://opensea.io/assets/base/0xabc/1?ref=auralis")!)

        guard case .success(let rootDestination) = policy.validate(emptyPath) else {
            Issue.record("Expected etherscan root URL to validate")
            return
        }
        #expect(rootDestination.pathDisplay == "/")

        guard case .success(let tokenDestination) = policy.validate(tokenPath) else {
            Issue.record("Expected OpenSea token URL to validate")
            return
        }
        #expect(tokenDestination.hostDisplay == "opensea.io")
        #expect(tokenDestination.pathDisplay == "/assets/base/0xabc/1")
        #expect(tokenDestination.fullURLDisplay == "https://opensea.io/assets/base/0xabc/1?ref=auralis")
    }
}
