import ReceiptsCore
//
//  OpenSeaLink.swift
//  Auralis
//
//  Created by Daniel Bell on 3/24/25.
//

import AuralisPrimaryModels
import SwiftUI

private enum ExternalLinkStyle {
    static let primaryGradient = [Color.accent, Color.accent.opacity(0.78)]
    static let secondaryGradient = [Color.deepBlue, Color.deepBlue.opacity(0.82)]
}

extension Chain {
    private static func externalDestination(label: String, host: String) -> ExternalLinkCandidateDestination? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host

        guard let url = components.url else {
            return nil
        }

        return ExternalLinkCandidateDestination(label: label, url: url)
    }

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

    var nftExplorerDestination: ExternalLinkCandidateDestination? {
        switch self {
        case .ethMainnet:
            return Self.externalDestination(label: "Etherscan", host: "etherscan.io")
        case .ethSepoliaTestnet:
            return Self.externalDestination(label: "Etherscan", host: "sepolia.etherscan.io")
        case .baseMainnet:
            return Self.externalDestination(label: "BaseScan", host: "basescan.org")
        case .baseSepoliaTestnet:
            return Self.externalDestination(label: "BaseScan", host: "sepolia.basescan.org")
        case .arbMainnet:
            return Self.externalDestination(label: "Arbiscan", host: "arbiscan.io")
        case .arbSepoliaTestnet:
            return Self.externalDestination(label: "Arbiscan", host: "sepolia.arbiscan.io")
        case .arbNovaMainnet:
            return Self.externalDestination(label: "Arbiscan", host: "nova.arbiscan.io")
        case .optMainnet:
            return Self.externalDestination(label: "Optimistic Etherscan", host: "optimistic.etherscan.io")
        case .optSepoliaTestnet:
            return Self.externalDestination(label: "Optimistic Etherscan", host: "sepolia-optimism.etherscan.io")
        case .polygonMainnet:
            return Self.externalDestination(label: "PolygonScan", host: "polygonscan.com")
        case .polygonAmoyTestnet:
            return Self.externalDestination(label: "PolygonScan", host: "amoy.polygonscan.com")
        default:
            return nil
        }
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

    @State private var pendingDestination: ExternalLinkConfirmationDestination?
    @State private var validationFailure: ExternalLinkValidationFailure?

    private let policy = ExternalLinkPolicy()

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
        VStack(alignment: .leading, spacing: 12) {
            if let validationFailure {
                AuraErrorBanner(
                    title: validationFailure.title,
                    message: validationFailure.message,
                    systemImage: "exclamationmark.triangle",
                    tone: .critical,
                    action: AuraFeedbackAction(
                        title: "Dismiss",
                        systemImage: "xmark",
                        handler: { self.validationFailure = nil }
                    )
                )
            }

            if let openSeaURL {
                Button {
                    presentConfirmation(
                        for: ExternalLinkCandidateDestination(label: "OpenSea", url: openSeaURL)
                    )
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        SystemImage("water.waves")
                            .font(.system(size: 18, weight: .bold))

                        VStack(alignment: .leading, spacing: 6) {
                            SystemFontText(
                                text: String(localized: "View on OpenSea"),
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
                            gradient: Gradient(colors: ExternalLinkStyle.primaryGradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("externalLink.openSea")
            }
        }
        .sheet(item: $pendingDestination) { destination in
            ExternalLinkConfirmationSheet(destination: destination) {
                confirmOpen(destination)
            }
        }
    }

    private func presentConfirmation(for candidate: ExternalLinkCandidateDestination) {
        validationFailure = nil

        switch policy.validate(candidate) {
        case .success(let destination):
            pendingDestination = destination
        case .failure(let failure):
            pendingDestination = nil
            validationFailure = failure
        }
    }

    private func confirmOpen(_ destination: ExternalLinkConfirmationDestination) {
        pendingDestination = nil

        Task {
            await ExternalLinkOpenFlow(
                eventLogger: ReceiptEventLogger(
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                ),
                openURL: { url in
                    openURL(url)
                }
            ).confirm(
                ExternalLinkOpenRequest(
                    label: destination.label,
                    url: destination.url,
                    surface: "newsfeed.nft_detail",
                    accountAddress: accountAddress,
                    chain: chain
                )
            )
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

    @State private var pendingDestination: ExternalLinkConfirmationDestination?
    @State private var validationFailure: ExternalLinkValidationFailure?

    private let policy = ExternalLinkPolicy()

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

    private var explorerDestination: ExternalLinkCandidateDestination? {
        chain.nftExplorerDestination
    }

    private var explorerURL: URL? {
        chain.nftExplorerURL(contractAddress: contractAddress, tokenId: tokenId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let validationFailure {
                AuraErrorBanner(
                    title: validationFailure.title,
                    message: validationFailure.message,
                    systemImage: "exclamationmark.triangle",
                    tone: .critical,
                    action: AuraFeedbackAction(
                        title: "Dismiss",
                        systemImage: "xmark",
                        handler: { self.validationFailure = nil }
                    )
                )
            }

            if let explorerDestination, let explorerURL {
                Button {
                    presentConfirmation(
                        for: ExternalLinkCandidateDestination(label: explorerDestination.label, url: explorerURL)
                    )
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        SystemImage("link.circle.fill")
                            .font(.system(size: 18, weight: .bold))

                        VStack(alignment: .leading, spacing: 6) {
                            SystemFontText(
                                text: String(localized: "View on \(explorerDestination.label)"),
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
                            gradient: Gradient(colors: ExternalLinkStyle.secondaryGradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("externalLink.explorer")
            }
        }
        .sheet(item: $pendingDestination) { destination in
            ExternalLinkConfirmationSheet(destination: destination) {
                confirmOpen(destination)
            }
        }
    }

    private func presentConfirmation(for candidate: ExternalLinkCandidateDestination) {
        validationFailure = nil

        switch policy.validate(candidate) {
        case .success(let destination):
            pendingDestination = destination
        case .failure(let failure):
            pendingDestination = nil
            validationFailure = failure
        }
    }

    private func confirmOpen(_ destination: ExternalLinkConfirmationDestination) {
        pendingDestination = nil

        Task {
            await ExternalLinkOpenFlow(
                eventLogger: ReceiptEventLogger(
                    receiptStore: ReceiptStores.live(modelContext: modelContext)
                ),
                openURL: { url in
                    openURL(url)
                }
            ).confirm(
                ExternalLinkOpenRequest(
                    label: destination.label,
                    url: destination.url,
                    surface: "newsfeed.nft_detail",
                    accountAddress: accountAddress,
                    chain: chain
                )
            )
        }
    }
}
