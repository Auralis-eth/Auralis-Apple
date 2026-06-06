import OperatorCore
@testable import Auralis
import AuralisPrimaryModels
import ExplorerAdapter
import Foundation
import Testing

struct ExternalLinkDestinationTests {
    private let contract = "0x1234567890abcdef1234567890abcdef12345678"

    @Test("OpenSea URLs are chain aware and unsupported chains stay hidden")
    func openSeaURLsFollowChainSupport() throws {
        let builder = OpenSeaDestinationBuilder()
        let baseURL = try builder.url(contract: contract, tokenID: "1", chain: .baseMainnet)
        #expect(baseURL.absoluteString == "https://opensea.io/assets/base/0x1234567890abcdef1234567890abcdef12345678/1")

        #expect(throws: ExplorerURLBuildError.unsupportedChain(.baseSepoliaTestnet)) {
            try builder.url(contract: contract, tokenID: "1", chain: .baseSepoliaTestnet)
        }
    }

    @Test("Explorer URLs use the chain-specific scanner host")
    func explorerURLsFollowChain() throws {
        let builder = ExplorerURLBuilder()
        let baseURL = try builder.url(for: .nft(contract: contract, tokenID: "1", chain: .baseMainnet))
        #expect(baseURL.absoluteString == "https://basescan.org/token/0x1234567890abcdef1234567890abcdef12345678?a=1")

        let arbitrumLabel = builder.label(for: .arbMainnet)
        #expect(arbitrumLabel == "Arbiscan")
    }

    @Test("external link policy accepts every supported explorer host")
    func policyAcceptsAllSupportedExplorerHosts() throws {
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
            ("PolygonScan", .polygonAmoyTestnet),
            ("WorldScan", .worldchainMainnet),
            ("WorldScan", .worldchainSepoliaTestnet),
            ("ShapeScan", .shapeMainnet),
            ("ShapeScan", .shapeSepoliaTestnet),
            ("Ink Explorer", .inkMainnet),
            ("Ink Explorer", .inkSepoliaTestnet),
            ("Uniscan", .unichainMainnet),
            ("Uniscan", .unichainSepoliaTestnet),
            ("Soneium Blockscout", .soneiumMainnet),
            ("Soneium Blockscout", .soneiumMinatoTestnet),
            ("BeraScan", .berachainMainnet),
            ("Zora Explorer", .zoraMainnet),
            ("Zora Explorer", .zoraSepoliaTestnet),
            ("PolynomialScan", .polynomialMainnet),
            ("PolynomialScan", .polynomialSepoliaTestnet),
        ]
        let builder = ExplorerURLBuilder()

        for (label, chain) in explorerCandidates {
            let url = try builder.url(for: .nft(contract: contract, tokenID: "1", chain: chain))

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
    func policyAcceptsApprovedHosts() throws {
        let policy = ExternalLinkPolicy()

        let openSeaURL = try #require(URL(string: "https://opensea.io/assets/base/0xabc/1"))
        let openSeaCollectionURL = try #require(URL(string: "https://opensea.io/collection/auralis"))
        let explorerAddressURL = try #require(URL(string: "https://etherscan.io/address/0x1234567890abcdef1234567890abcdef12345678"))
        let explorerTxURL = try #require(URL(string: "https://etherscan.io/tx/0xabc"))
        let ipfsIOURL = try #require(URL(string: "https://ipfs.io/ipfs/QmHash"))
        let cloudflareIPFSURL = try #require(URL(string: "https://cloudflare-ipfs.com/ipfs/QmHash"))
        let pinataIPFSURL = try #require(URL(string: "https://gateway.pinata.cloud/ipfs/QmHash"))
        let arweaveURL = try #require(URL(string: "https://arweave.net/tx/example"))

        let approvedCandidates = [
            ExternalLinkCandidateDestination(label: "OpenSea", url: openSeaURL),
            ExternalLinkCandidateDestination(label: "OpenSea Collection", url: openSeaCollectionURL),
            ExternalLinkCandidateDestination(label: "Explorer Address", url: explorerAddressURL),
            ExternalLinkCandidateDestination(label: "Explorer Transaction", url: explorerTxURL),
            ExternalLinkCandidateDestination(label: "IPFS", url: ipfsIOURL),
            ExternalLinkCandidateDestination(label: "IPFS", url: cloudflareIPFSURL),
            ExternalLinkCandidateDestination(label: "IPFS", url: pinataIPFSURL),
            ExternalLinkCandidateDestination(label: "Arweave", url: arweaveURL)
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

    @Test("external link policy rejects root-level action URLs on approved hosts")
    func policyRejectsRootLevelActionURLs() throws {
        let policy = ExternalLinkPolicy()

        let explorerRootURL = try #require(URL(string: "https://etherscan.io"))
        let openSeaRootURL = try #require(URL(string: "https://opensea.io/"))
        let arweaveRootURL = try #require(URL(string: "https://arweave.net"))

        let rootCandidates = [
            ExternalLinkCandidateDestination(label: "Explorer Root", url: explorerRootURL),
            ExternalLinkCandidateDestination(label: "OpenSea Root", url: openSeaRootURL),
            ExternalLinkCandidateDestination(label: "Arweave Root", url: arweaveRootURL)
        ]

        for candidate in rootCandidates {
            let host = candidate.url.host() ?? ""

            #expect(
                policy.validate(candidate) == .failure(.unsupportedPath(host: host, path: "/")),
                "Expected root path to be rejected for \(candidate.url.absoluteString)"
            )
        }
    }

    @Test("external link policy rejects unsupported and suspicious destinations with typed failures")
    func policyRejectsBlockedDestinations() throws {
        let policy = ExternalLinkPolicy()

        let unsupportedHostURL = try #require(URL(string: "https://example.com/phish"))
        let unsupportedPathURL = try #require(URL(string: "https://opensea.io/settings"))
        let missingHostURL = try #require(URL(string: "https:///missing-host"))

        let unsupportedHost = ExternalLinkCandidateDestination(label: "Bad", url: unsupportedHostURL)
        let unsupportedPath = ExternalLinkCandidateDestination(label: "Bad Path", url: unsupportedPathURL)
        let missingHost = ExternalLinkCandidateDestination(label: "Broken", url: missingHostURL)
        let badSchemes = [
            "javascript:alert(1)",
            "file:///tmp/test",
            "data:text/plain,hello",
            "auralis://wallet"
        ]

        #expect(policy.validate(unsupportedHost) == .failure(.unsupportedHost("example.com")))
        #expect(policy.validate(unsupportedPath) == .failure(.unsupportedPath(host: "opensea.io", path: "/settings")))
        #expect(policy.validate(missingHost) == .failure(.missingHost))

        for rawValue in badSchemes {
            let badURL = try #require(URL(string: rawValue))
            let candidate = ExternalLinkCandidateDestination(label: "Blocked", url: badURL)
            guard case .failure(.invalidScheme) = policy.validate(candidate) else {
                Issue.record("Expected invalid scheme failure for \(rawValue)")
                continue
            }
        }
    }

    @Test("external link policy preserves user-visible host and path displays")
    func policyBuildsDisplayFields() throws {
        let policy = ExternalLinkPolicy()

        let tokenPathURL = try #require(URL(string: "https://opensea.io/assets/base/0xabc/1?ref=auralis"))
        let tokenPath = ExternalLinkCandidateDestination(label: "OpenSea", url: tokenPathURL)

        guard case .success(let tokenDestination) = policy.validate(tokenPath) else {
            Issue.record("Expected OpenSea token URL to validate")
            return
        }
        #expect(tokenDestination.hostDisplay == "opensea.io")
        #expect(tokenDestination.pathDisplay == "/assets/base/0xabc/1")
        #expect(tokenDestination.routeTypeDisplay == "Marketplace")
        #expect(tokenDestination.fullURLDisplay == "https://opensea.io/assets/base/0xabc/1?ref=auralis")
        #expect(tokenDestination.fullURLDisplay == tokenDestination.url.absoluteString)
    }
}
