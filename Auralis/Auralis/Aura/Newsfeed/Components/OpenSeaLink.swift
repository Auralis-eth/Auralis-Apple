//
//  OpenSeaLink.swift
//  Auralis
//
//  Created by Daniel Bell on 3/24/25.
//

import SwiftUI

struct NFTExternalDestination: Equatable {
    let label: String
    let url: URL
}

extension Chain {
    var openSeaChainSlug: String? {
        switch self {
        case .ethMainnet:
            return "ethereum"
        case .baseMainnet:
            return "base"
        case .arbMainnet:
            return "arbitrum"
        case .optMainnet:
            return "optimism"
        case .polygonMainnet:
            return "matic"
        case .zoraMainnet:
            return "zora"
        default:
            return nil
        }
    }

    var nftExplorerDestination: NFTExternalDestination? {
        let host: String
        let label: String

        switch self {
        case .ethMainnet:
            host = "etherscan.io"
            label = "Etherscan"
        case .ethSepoliaTestnet:
            host = "sepolia.etherscan.io"
            label = "Etherscan"
        case .baseMainnet:
            host = "basescan.org"
            label = "BaseScan"
        case .baseSepoliaTestnet:
            host = "sepolia.basescan.org"
            label = "BaseScan"
        case .arbMainnet:
            host = "arbiscan.io"
            label = "Arbiscan"
        case .arbSepoliaTestnet:
            host = "sepolia.arbiscan.io"
            label = "Arbiscan"
        case .arbNovaMainnet:
            host = "nova.arbiscan.io"
            label = "Arbiscan"
        case .optMainnet:
            host = "optimistic.etherscan.io"
            label = "Optimistic Etherscan"
        case .optSepoliaTestnet:
            host = "sepolia-optimism.etherscan.io"
            label = "Optimistic Etherscan"
        case .polygonMainnet:
            host = "polygonscan.com"
            label = "PolygonScan"
        case .polygonAmoyTestnet:
            host = "amoy.polygonscan.com"
            label = "PolygonScan"
        default:
            return nil
        }

        return NFTExternalDestination(label: label, url: URL(string: "https://\(host)")!)
    }

    func openSeaURL(contractAddress: String, tokenId: String) -> URL? {
        guard let chainSlug = openSeaChainSlug else {
            return nil
        }

        return URL(string: "https://opensea.io/assets/\(chainSlug)/\(contractAddress)/\(tokenId)")
    }

    func nftExplorerURL(contractAddress: String, tokenId: String) -> URL? {
        guard let destination = nftExplorerDestination else {
            return nil
        }

        return URL(string: "\(destination.url.absoluteString)/token/\(contractAddress)?a=\(tokenId)")
    }
}

struct OpenSeaLink: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let chain: Chain
    let contractAddress: String
    let tokenId: String
    let accountAddress: String?

    init(chain: Chain,
         contractAddress: String,
         tokenId: String,
         accountAddress: String? = nil) {
        self.chain = chain
        self.contractAddress = contractAddress
        self.tokenId = tokenId
        self.accountAddress = accountAddress
    }

    private var openSeaURL: URL? {
        chain.openSeaURL(contractAddress: contractAddress, tokenId: tokenId)
    }

    var body: some View {
        if let openSeaURL {
            Button {
                ReceiptEventLogger(
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                ).recordExternalLinkOpened(
                    label: "OpenSea",
                    url: openSeaURL,
                    surface: "newsfeed.nft_detail",
                    accountAddress: accountAddress,
                    chain: chain
                )
                openURL(openSeaURL)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    SystemImage("water.waves")
                        .font(.system(size: 18, weight: .bold))

                    VStack(alignment: .leading, spacing: 6) {
                        SystemFontText(
                            text: "View on OpenSea",
                            size: 16,
                            weight: .semibold
                        )

                        AuraTrustLabel(kind: .link)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hexString: "2081E2"),
                            Color(hexString: "2081E2").opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct EtherscanLink: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    let chain: Chain
    let contractAddress: String
    let tokenId: String
    let accountAddress: String?

    init(
        chain: Chain,
        contractAddress: String,
        tokenId: String,
        accountAddress: String? = nil
    ) {
        self.chain = chain
        self.contractAddress = contractAddress
        self.tokenId = tokenId
        self.accountAddress = accountAddress
    }

    private var explorerDestination: NFTExternalDestination? {
        chain.nftExplorerDestination
    }

    private var explorerURL: URL? {
        chain.nftExplorerURL(contractAddress: contractAddress, tokenId: tokenId)
    }

    var body: some View {
        if let explorerDestination, let explorerURL {
            Button {
                ReceiptEventLogger(
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                ).recordExternalLinkOpened(
                    label: explorerDestination.label,
                    url: explorerURL,
                    surface: "newsfeed.nft_detail",
                    accountAddress: accountAddress,
                    chain: chain
                )
                openURL(explorerURL)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    SystemImage("link.circle.fill")
                        .font(.system(size: 18, weight: .bold))

                    VStack(alignment: .leading, spacing: 6) {
                        SystemFontText(
                            text: "View on \(explorerDestination.label)",
                            size: 16,
                            weight: .semibold
                        )

                        AuraTrustLabel(kind: .link)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hexString: "3498DB"),
                            Color(hexString: "2980B9").opacity(0.8)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
