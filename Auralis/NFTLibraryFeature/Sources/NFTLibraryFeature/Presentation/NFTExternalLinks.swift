import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import ExplorerAdapter
import OperatorCore
import SwiftUI

private enum NFTExternalLinkStyle {
    static let primaryGradient = [Color.accent, Color.accent.opacity(0.78)]
    static let secondaryGradient = [Color.deepBlue, Color.deepBlue.opacity(0.82)]
}

public struct NFTExternalLinkConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    public let destination: ExternalLinkConfirmationDestination
    public let onConfirm: @MainActor () -> Void

    public init(destination: ExternalLinkConfirmationDestination, onConfirm: @escaping @MainActor () -> Void) {
        self.destination = destination
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NFTLibraryScenicScreen(horizontalPadding: 12, verticalPadding: 12, contentAlignment: Alignment.top) {
            ScrollView {
                AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Open External Link?")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.textPrimary)

                            Text("You are leaving Auralis and opening Safari. Review the destination before continuing.")
                                .font(.body)
                                .foregroundStyle(Color.textSecondary)
                        }

                        AuraTrustLabel(kind: .link)
                        verifiedHostField(destination.hostDisplay)
                        destinationField(title: "Destination", value: destination.label, font: .headline)
                        destinationField(title: "Path", value: destination.pathDisplay, font: .body.monospaced())
                        destinationField(title: "Full URL", value: destination.fullURLDisplay, font: .footnote.monospaced())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("externalLink.confirmationSheet")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    AuraActionButton("Open in Safari", systemImage: "safari", style: .hero) {
                        onConfirm()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Opens this approved destination in Safari.")
                    .accessibilityIdentifier("externalLink.confirm")

                    AuraActionButton("Cancel", systemImage: "xmark", style: .surface) {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Stays in Auralis and closes this confirmation sheet.")
                    .accessibilityIdentifier("externalLink.cancel")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
        }
        .presentationDragIndicator(Visibility.visible)
        .presentationDetents([PresentationDetent.medium, PresentationDetent.large])
    }

    private func verifiedHostField(_ host: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verified Host")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)

            Text(host)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accent.opacity(0.14))
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accent.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func destinationField(title: String, value: String, font: Font) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)

            Text(value)
                .font(font)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

public struct NFTMarketplaceLink: View {
    public let nft: NFT
    public let dependencies: NFTLibraryDependencies
    @State private var pendingDestination: ExternalLinkConfirmationDestination?
    @State private var validationFailure: ExternalLinkValidationFailure?

    private let policy = ExternalLinkPolicy()
    private let builder = OpenSeaDestinationBuilder()

    public init(nft: NFT, dependencies: NFTLibraryDependencies) {
        self.nft = nft
        self.dependencies = dependencies
    }

    private var destination: ExternalLinkCandidateDestination? {
        guard let chain = nft.network,
              let contractAddress = nft.contract.address,
              let url = try? builder.url(contract: contractAddress, tokenID: nft.tokenId, chain: chain) else {
            return nil
        }

        return ExternalLinkCandidateDestination(label: "OpenSea", url: url)
    }

    public var body: some View {
        externalLinkButton(
            destination: destination,
            title: "View on OpenSea",
            systemImage: "water.waves",
            gradient: NFTExternalLinkStyle.primaryGradient,
            accessibilityIdentifier: "externalLink.openSea"
        )
    }

    @ViewBuilder
    private func externalLinkButton(
        destination: ExternalLinkCandidateDestination?,
        title: String,
        systemImage: String,
        gradient: [Color],
        accessibilityIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let validationFailure {
                AuraErrorBanner(
                    title: validationFailure.title,
                    message: validationFailure.message,
                    systemImage: "exclamationmark.triangle",
                    tone: .critical,
                    action: AuraFeedbackAction(title: "Dismiss", systemImage: "xmark") {
                        self.validationFailure = nil
                    }
                )
            }

            if let destination {
                Button {
                    presentConfirmation(for: destination)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        SystemImage(systemImage)
                            .font(.system(size: 18, weight: .bold))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 6) {
                            SystemFontText(text: title, size: 16, weight: .semibold)
                            AuraTrustLabel(kind: .link)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: gradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(accessibilityIdentifier)
            }
        }
        .sheet(item: $pendingDestination) { destination in
            NFTExternalLinkConfirmationSheet(destination: destination) {
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
        guard let chain = nft.network else { return }
        Task {
            await dependencies.openExternalLink(
                ExternalLinkOpenRequest(
                    label: destination.label,
                    url: destination.url,
                    surface: "nft_library.detail",
                    accountAddress: nft.accountAddress,
                    chain: chain,
                    auditRequirement: .durable
                )
            )
        }
    }
}

public struct NFTExplorerLink: View {
    public let nft: NFT
    public let dependencies: NFTLibraryDependencies
    @State private var pendingDestination: ExternalLinkConfirmationDestination?
    @State private var validationFailure: ExternalLinkValidationFailure?

    private let policy = ExternalLinkPolicy()
    private let builder = ExplorerURLBuilder()

    public init(nft: NFT, dependencies: NFTLibraryDependencies) {
        self.nft = nft
        self.dependencies = dependencies
    }

    private var destination: ExternalLinkCandidateDestination? {
        guard let chain = nft.network,
              let contractAddress = nft.contract.address,
              let label = builder.label(for: chain),
              let url = try? builder.url(for: .nft(contract: contractAddress, tokenID: nft.tokenId, chain: chain)) else {
            return nil
        }

        return ExternalLinkCandidateDestination(label: label, url: url)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let validationFailure {
                AuraErrorBanner(
                    title: validationFailure.title,
                    message: validationFailure.message,
                    systemImage: "exclamationmark.triangle",
                    tone: .critical,
                    action: AuraFeedbackAction(title: "Dismiss", systemImage: "xmark") {
                        self.validationFailure = nil
                    }
                )
            }

            if let destination {
                Button {
                    presentConfirmation(for: destination)
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        SystemImage("link.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 6) {
                            SystemFontText(text: "View on \(destination.label)", size: 16, weight: .semibold)
                            AuraTrustLabel(kind: .link)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: NFTExternalLinkStyle.secondaryGradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("externalLink.explorer")
            }
        }
        .sheet(item: $pendingDestination) { destination in
            NFTExternalLinkConfirmationSheet(destination: destination) {
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
        guard let chain = nft.network else { return }
        Task {
            await dependencies.openExternalLink(
                ExternalLinkOpenRequest(
                    label: destination.label,
                    url: destination.url,
                    surface: "nft_library.detail",
                    accountAddress: nft.accountAddress,
                    chain: chain,
                    auditRequirement: .durable
                )
            )
        }
    }
}
