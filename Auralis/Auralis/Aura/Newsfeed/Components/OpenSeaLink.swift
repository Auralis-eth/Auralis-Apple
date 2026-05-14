import ReceiptsCore
import ReceiptStorage
//
//  OpenSeaLink.swift
//  Auralis
//
//  Created by Daniel Bell on 3/24/25.
//

import AuralisPrimaryModels
import ExplorerAdapter
import OperatorCore
import SwiftUI

private enum ExternalLinkStyle {
    static let primaryGradient = [Color.accent, Color.accent.opacity(0.78)]
    static let secondaryGradient = [Color.deepBlue, Color.deepBlue.opacity(0.82)]
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
    private let openSeaDestinationBuilder = OpenSeaDestinationBuilder()

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
        try? openSeaDestinationBuilder.url(contract: contractAddress, tokenID: tokenId, chain: chain)
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
                eventLogger: AppExternalLinkEventLogger(
                    receiptEventLogger: ReceiptEventLogger(
                        receiptStore: ReceiptStores.live(modelContext: modelContext)
                    )
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
    private let explorerURLBuilder = ExplorerURLBuilder()

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
        guard let label = explorerURLBuilder.label(for: chain),
              let url = explorerURL else {
            return nil
        }

        return ExternalLinkCandidateDestination(label: label, url: url)
    }

    private var explorerURL: URL? {
        try? explorerURLBuilder.url(for: .nft(contract: contractAddress, tokenID: tokenId, chain: chain))
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
                eventLogger: AppExternalLinkEventLogger(
                    receiptEventLogger: ReceiptEventLogger(
                        receiptStore: ReceiptStores.live(modelContext: modelContext)
                    )
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
