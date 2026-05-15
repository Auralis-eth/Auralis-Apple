import AuralisPrimaryModels
import AuraUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

public struct NFTLibraryCardView: View {
    public let nft: NFT
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var actionRailWidth = 70

    public init(nft: NFT) {
        self.nft = nft
    }

    private var detailsWidthRatio: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 0.78 : 0.65
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                imageView

                HStack(alignment: .bottom, spacing: 16) {
                    ScrollView {
                        NFTLibraryGlassCard(cornerRadius: 30) {
                            NFTLibraryCardDetailsView(nft: nft, isExpanded: $isExpanded)
                        }
                            .padding(.leading, 15)
                            .frame(maxWidth: geo.size.width * detailsWidthRatio, alignment: .leading)
                    }
                    .defaultScrollAnchor(.top)
                    .scrollDisabled(!isExpanded)
                    .frame(maxHeight: isExpanded ? geo.size.height * 0.4 : nil)

                    NFTLibraryCardButtons(nft: nft)
                        .frame(width: max(actionRailWidth, 70))
                        .padding(.trailing, 5)
                }
                .padding(.horizontal, 15)
                .padding(.bottom, geo.safeAreaInsets.bottom + 15)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(.all)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var imageView: some View {
        if let imageURL = NFTLibraryPresentation.imageURL(for: nft) {
            #if canImport(UIKit)
            NFTCachedAsyncImage(url: imageURL)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .clipped()
                .accessibilityLabel(NFTLibraryPresentation.displayTitle(for: nft))
            #else
            AsyncImage(url: imageURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .accessibilityLabel(NFTLibraryPresentation.displayTitle(for: nft))
            #endif
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .ignoresSafeArea()

                VStack {
                    SystemImage("photo")
                        .font(.largeTitle)
                    Text("Image unavailable")
                        .font(.footnote)
                }
                .foregroundStyle(Color.gray)
            }
            .aspectRatio(contentMode: .fit)
            .clipped()
            .accessibilityLabel("NFT image unavailable")
        }
    }
}

public struct NFTLibraryCardButtons: View {
    public let nft: NFT
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var copyConfirmationDismissTask: Task<Void, Never>?
    @State private var isShowingCopyConfirmation = false

    public init(nft: NFT) {
        self.nft = nft
    }

    public var body: some View {
        cardButtons
            .onDisappear {
                copyConfirmationDismissTask?.cancel()
                copyConfirmationDismissTask = nil
            }
    }

    @ViewBuilder
    private var cardButtons: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                buttonStack
                    .buttonStyle(.glassProminent)
                    .glassEffectUnion(id: "nftlibrarycardbuttons", namespace: namespace)
            }
        } else {
            buttonStack
                .background(Color.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private var buttonStack: some View {
            VStack {
                ZStack {
                    Circle()
                        .stroke(Color.textPrimary, lineWidth: 2)
                        .frame(width: 25, height: 25)

                    SystemImage("circle.dotted")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary.opacity(0.85))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHidden(true)

                Menu {
                    Button {
                        copyNFTIdentifier()
                    } label: {
                        Label("Copy ID", systemImage: "doc.on.doc")
                    }
                } label: {
                    SystemImage("ellipsis")
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("More actions")
                .accessibilityHint("Shows actions for this NFT")
            }
            .font(.title2)
            .padding()
            .tint(Color.surface.opacity(0.8))
            .overlay(alignment: .top) {
                if isShowingCopyConfirmation {
                    AuraPill("Copied", systemImage: "checkmark.circle.fill", emphasis: .success)
                        .offset(y: -28)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: isShowingCopyConfirmation)
    }

    private func copyNFTIdentifier() {
        #if canImport(UIKit)
        UIPasteboard.general.string = nft.id
        #endif
        presentCopyConfirmation()
    }

    private func presentCopyConfirmation() {
        copyConfirmationDismissTask?.cancel()
        isShowingCopyConfirmation = true
        copyConfirmationDismissTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isShowingCopyConfirmation = false
            }
        }
    }
}

public struct NFTLibraryCardDetailsView: View {
    public let nft: NFT
    @Binding private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(nft: NFT, isExpanded: Binding<Bool>) {
        self.nft = nft
        _isExpanded = isExpanded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading) {
                HeadlineFontText(nft.collection?.name ?? "Unknown Collection")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)

                HStack {
                    FootnoteFontText("Updated: ")
                    SecondaryCaptionFontText(formattedUpdateTime)
                }
            }

            if let description = nft.nftDescription, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(isExpanded ? nil : 5)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }

            Button {
                withAnimation(reduceMotion ? nil : .snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    SubheadlineFontText(isExpanded ? "Show Less Info" : "Show More Info")
                        .fontWeight(.medium)

                    SystemImage(isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonBorderShape(.capsule)
            .tint(.surface.opacity(0.8))

            if isExpanded {
                NFTLibraryExpandedDetailsView(nft: nft)
                    .padding(.top)
            }
        }
        .padding()
    }

    private var formattedUpdateTime: String {
        guard let timeUpdated = nft.timeLastUpdated,
              let date = parseISODate(timeUpdated) else {
            return "Not available"
        }

        return RelativeDateTimeFormatter().localizedString(for: min(date, Date()), relativeTo: Date())
    }

    private func parseISODate(_ dateString: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: dateString) {
            return date
        }

        return ISO8601DateFormatter().date(from: dateString)
    }
}

public struct NFTLibraryExpandedDetailsView: View {
    public let nft: NFT

    public init(nft: NFT) {
        self.nft = nft
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(nft.name ?? "Unnamed NFT")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    HeadlineFontText("Technical Details")
                        .gridCellColumns(2)
                }
                detailRow("Contract", nft.contract.address ?? "N/A")
                detailRow("Token ID", nft.tokenId)
                detailRow("Token Standard", nft.tokenType ?? "Unknown")
                detailRow("Blockchain", nft.network?.networkName ?? "Unknown")
            }

            if let attributes = nft.raw?.metadata?.attributes, !attributes.isEmpty {
                HeadlineFontText("Traits")
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(attributes) { attribute in
                            VStack(alignment: .center) {
                                if let traitType = attribute.traitType {
                                    SecondaryCaptionFontText(traitType)
                                }
                                Caption2FontText(attribute.value)
                            }
                            .padding(8)
                            .background(Color.surface.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 8))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } else {
                SecondaryCaptionFontText("No traits available")
                    .padding(.top, 8)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            SubheadlineFontText(title)
            SubheadlineFontText(value)
                .truncationMode(.middle)
        }
    }
}
