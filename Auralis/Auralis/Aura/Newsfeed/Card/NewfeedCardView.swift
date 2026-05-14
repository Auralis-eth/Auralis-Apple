import ReceiptsCore
import ReceiptStorage
//
//  NewfeedCardView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import AuralisPrimaryModels
import SwiftUI
import AuraUI
#if canImport(UIKit)
import UIKit
#endif

struct NewsFeedCardView: View {
    let nft: NFT
    @State private var isExpanded: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var actionRailWidth = 70

    private var detailsWidthRatio: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 0.78 : 0.65
    }

    @ViewBuilder
    private var imageView: some View {
        if let imageUrlString = nft.image?.originalUrl,
           !imageUrlString.isEmpty,
           let imageUrl = URL(string: imageUrlString) {
            CachedAsyncImage(url: imageUrl)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .clipped()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .ignoresSafeArea()

                VStack {
                    SystemImage("photo")
                        .font(.system(size: 50))

                    if let urlString = nft.image?.originalUrl,
                       !urlString.isEmpty {
                        Text(urlString)
                            .font(.footnote)
                    }
                }
                .foregroundStyle(Color.gray)
            }
            .aspectRatio(contentMode: .fit)
            .clipped()
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background NFT image
                imageView

                HStack(alignment: .bottom, spacing: 16) {
                    // NFT details
                    ScrollView {
                        NewsFeedCardDetailsView(nft: nft, isExpanded: $isExpanded)
                            .glassEffect(.regular.tint(.surface),
                                       in: .rect(cornerRadius: 30, style: .continuous))
                            .padding(.leading, 15)
                            .frame(maxWidth: geo.size.width * detailsWidthRatio, alignment: .leading)
                    }
                    .defaultScrollAnchor(.top)
                    .scrollDisabled(!isExpanded)
                    .frame(maxHeight: isExpanded ? geo.size.height * 0.4 : nil)

                    // Action buttons
                    NewsFeedCardButtons(nft: nft)
                        .frame(width: max(actionRailWidth, 70))
                        .padding(.trailing, 5)
                }
                .padding(.horizontal, 15)
                .padding(.bottom, geo.safeAreaInsets.bottom + 15)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea(.all)
    }

}

struct NewsFeedCardButtons: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.modelContext) private var modelContext
    @Namespace private var namespace
    @State private var copyConfirmationDismissTask: Task<Void, Never>?
    @State private var isShowingCopyConfirmation = false
    let nft: NFT

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    var body: some View {
        GlassEffectContainer {
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
                    Button(action: {
                        copyNFTIdentifier()
                    }, label: {
                        Label(String(localized: "Copy ID"), systemImage: "doc.on.doc")
                    })
                } label: {
                    SystemImage("ellipsis")
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(localized: "More actions"))
                .accessibilityHint(String(localized: "Shows actions for this NFT"))
            }
            .font(.title2)
            .padding()
            .buttonStyle(.glassProminent)
            .tint(Color.surface.opacity(0.8))
            .glassEffectUnion(id: "newsfeedcardbuttons", namespace: namespace)
            .overlay(alignment: .top) {
                if isShowingCopyConfirmation {
                    AuraPill(
                        String(localized: "Copied"),
                        systemImage: "checkmark.circle.fill",
                        emphasis: .success
                    )
                    .offset(y: -28)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: isShowingCopyConfirmation)
        }
        .onDisappear {
            copyConfirmationDismissTask?.cancel()
            copyConfirmationDismissTask = nil
        }
    }

    private func copyNFTIdentifier() {
#if canImport(UIKit)
        UIPasteboard.general.string = nft.id
#endif
        haptics.notification(.success)
        presentCopyConfirmation()
        Task {
            _ = try? await ReceiptEventLogger(
                receiptStore: ReceiptStores.live(modelContext: modelContext)
            ).recordCopyAction(
                subject: "nft.id",
                value: nft.id,
                surface: "newsfeed.card",
                accountAddress: nft.accountAddress,
                chain: nft.network
            )
        }
    }

    private func presentCopyConfirmation() {
        copyConfirmationDismissTask?.cancel()
        isShowingCopyConfirmation = true
        copyConfirmationDismissTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                isShowingCopyConfirmation = false
            }
        }
    }
}

struct NewsFeedCardExpandedDetailsView: View {
    let nft: NFT

    private var sortedTags: [Tag] {
        (nft.tags ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and description
            SystemFontText(text: nft.name ?? String(localized: "Unnamed NFT"), size: 18, weight: .semibold)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                // Headline can be outside the grid or as a header row
                GridRow {
                    // Use .gridCellColumns(2) to make the header span both columns
                    HeadlineFontText(String(localized: "Technical Details"))
                        .gridCellColumns(2)
                }

                // Your detail rows
                GridRow {
                    SubheadlineFontText(String(localized: "Contract"))
                    SubheadlineFontText(nft.contract.address ?? String(localized: "N/A"))
                        .truncationMode(.middle)
                }
                GridRow {
                    SubheadlineFontText(String(localized: "Token ID"))
                    SubheadlineFontText(nft.tokenId)
                        .truncationMode(.middle)
                }
                GridRow {
                    SubheadlineFontText(String(localized: "Token Standard"))
                    SubheadlineFontText(nft.tokenType ?? String(localized: "Unknown"))
                }
                GridRow {
                    SubheadlineFontText(String(localized: "Blockchain"))
                    SubheadlineFontText(nft.network?.networkName ?? String(localized: "Unknown"))
                }
            }

            // Attributes/Traits section
            if let metadata = nft.raw?.metadata, let attributes = metadata.attributes, !attributes.isEmpty {
                HeadlineFontText(String(localized: "Traits"))
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
                        }
                    }
                }
            } else {
                SecondaryCaptionFontText(String(localized: "No traits available"))
                    .padding(.top, 8)
            }

            if !sortedTags.isEmpty {
                HeadlineFontText(String(localized: "Tags"))
                    .padding(.top, 8)

                FlowTagRow(tags: sortedTags)
            }

            if let chain = nft.network,
               let contractAddress = nft.contract.address {
                OpenSeaLink(
                    chain: chain,
                    contractAddress: contractAddress,
                    tokenId: nft.tokenId,
                    accountAddress: nft.accountAddress
                )
                EtherscanLink(
                    chain: chain,
                    contractAddress: contractAddress,
                    tokenId: nft.tokenId,
                    accountAddress: nft.accountAddress
                )
            }

        }
    }
}

private struct FlowTagRow: View {
    let tags: [Tag]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunkedTags, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row, id: \.name) { tag in
                        TagChip(tag: tag)
                    }
                }
            }
        }
    }

    private var chunkedTags: [[Tag]] {
        stride(from: 0, to: tags.count, by: 3).map { start in
            Array(tags[start..<min(start + 3, tags.count)])
        }
    }
}

private struct TagChip: View {
    let tag: Tag

    private var tintColor: Color {
        if Color.rgbaComponents(from: tag.color) != nil {
            return Color(hexString: tag.color)
        }

        return .accent
    }

    var body: some View {
        PrimaryCaptionFontText(tag.name)
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tintColor.opacity(0.22))
            .overlay {
                Capsule()
                    .strokeBorder(tintColor.opacity(0.55), lineWidth: 1)
            }
            .clipShape(.capsule)
    }
}

struct NewsFeedCardDetailsView: View {
    let nft: NFT
    @Binding var isExpanded: Bool

    // Modern, efficient, and localizable formatters
    private static let isoFormatters: [ISO8601DateFormatter] = {
        var f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]

        return [f1, f2]
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let rf = RelativeDateTimeFormatter()
        rf.unitsStyle = .short // or .full for accessibility
        return rf
    }()

    var body: some View {
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

            // NFT Description
            if let description = nft.nftDescription, !description.isEmpty {
                SystemFontText(
                    text: description,
                    size: 15,
                    weight: .medium
                )
                .lineLimit(isExpanded ? nil : 5)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
            }

            Button {
                withAnimation {
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
                NewsFeedCardExpandedDetailsView(nft: nft)
                    .padding(.top)
            }
        }
        .padding()
    }

    // Modern computed property using RelativeDateTimeFormatter
    private var formattedUpdateTime: String {
        guard let timeUpdated = nft.timeLastUpdated,
              let date = parseISODate(timeUpdated) else {
            return "Not available"
        }

        let now = Date()
        // Handle future dates by clamping them to "just now"
        if date > now {
            return Self.relativeFormatter.localizedString(fromTimeInterval: -1)
        }

        return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    // Helper function to parse ISO dates with fallback formatters
    private func parseISODate(_ dateString: String) -> Date? {
        for formatter in Self.isoFormatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
}
