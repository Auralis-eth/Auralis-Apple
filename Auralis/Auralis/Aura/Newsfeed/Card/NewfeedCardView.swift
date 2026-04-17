//
//  NewfeedCardView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct NewsFeedCardView: View {
    let nft: NFT
    @State private var isExpanded: Bool = false

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
                    if isExpanded {
                        ScrollView {
                            NewsFeedCardDetailsView(nft: nft, isExpanded: $isExpanded)
                                .glassEffect(.regular.tint(.surface),
                                           in: .rect(cornerRadius: 30, style: .continuous))
                                .padding(.leading, 15)
                                .frame(maxWidth: geo.size.width * 0.65, alignment: .leading)
                        }
                        .defaultScrollAnchor(.top)
                        .frame(maxHeight: geo.size.height * 0.4)
                    } else {
                        NewsFeedCardDetailsView(nft: nft, isExpanded: $isExpanded)
                            .glassEffect(.regular.tint(.surface),
                                       in: .rect(cornerRadius: 30, style: .continuous))
                            .padding(.leading, 15)
                            .frame(maxWidth: geo.size.width * 0.65, alignment: .leading)
                    }

                    // Action buttons
                    NewsFeedCardButtons(nft: nft)
                        .frame(width: 70) // fixed width so it never clips offscreen
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
    @Environment(\.modelContext) private var modelContext
    @Namespace private var namespace
    let nft: NFT

    var body: some View {
        GlassEffectContainer {
            VStack {
                Button(action: {}, label: {
                    ZStack {
                        Circle()
                            .stroke(Color.textPrimary, lineWidth: 2)
                            .frame(width: 25, height: 25)

                        // Profile image placeholder
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 20, height: 20)
                    }
                })

                Menu {
                    Button(action: {
                        copyNFTIdentifier()
                    }) {
                        Label("Copy ID", systemImage: "doc.on.doc")
                    }
                } label: {
                    SystemImage("ellipsis")
                        .foregroundStyle(Color.textPrimary)
                }

                Button(action: {
                    // Like action
                }, label: {
                    PrimaryTextSystemImage("heart")
                })

                Button(action: {
                    // Comment action
                }, label: {
                    PrimaryTextSystemImage("bubble.right")
                })

                Button(action: {
                    // Share action
                }, label: {
                    PrimaryTextSystemImage("paperplane")
                })

                Button(action: {
                    // Bookmark action
                }, label: {
                    PrimaryTextSystemImage("bookmark")
                })
            }
            .font(.title2)
            .padding()
            .buttonStyle(.glassProminent)
            .tint(Color.surface.opacity(0.8))
            .glassEffectUnion(id: "newsfeedcardbuttons", namespace: namespace)

        }
    }

    private func copyNFTIdentifier() {
#if canImport(UIKit)
        UIPasteboard.general.string = nft.id
#endif
        ReceiptEventLogger(
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

struct NewsFeedCardExpandedDetailsView: View {
    let nft: NFT
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and description
            SystemFontText(text: nft.name ?? "Unnamed NFT", size: 18, weight: .semibold)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                // Headline can be outside the grid or as a header row
                GridRow {
                    // Use .gridCellColumns(2) to make the header span both columns
                    HeadlineFontText("Technical Details")
                        .gridCellColumns(2)
                }

                // Your detail rows
                GridRow {
                    SubheadlineFontText("Contract") // Custom view assumed
                    SubheadlineFontText(nft.contract.address ?? "N/A")
                        .truncationMode(.middle)
                }
                GridRow {
                    SubheadlineFontText("Token ID")
                    SubheadlineFontText(nft.tokenId)
                        .truncationMode(.middle)
                }
                GridRow {
                    SubheadlineFontText("Token Standard")
                    SubheadlineFontText(nft.tokenType ?? "Unknown")
                }
                GridRow {
                    SubheadlineFontText("Blockchain")
                    SubheadlineFontText(nft.network?.networkName ?? "Unknown")
                }
            }

            // Attributes/Traits section
            if let metadata = nft.raw?.metadata, let attributes = metadata.attributes, !attributes.isEmpty {
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
                            .cornerRadius(8)
                        }
                    }
                }
            } else {
                SecondaryCaptionFontText("No traits available")
                    .padding(.top, 8)
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

            // Category display (placeholder)
            HStack {
                Spacer()
                PrimaryText("Category")
                PrimaryCaptionFontText("Category Selector")
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accent.opacity(0.3))
                    .cornerRadius(16)
                Spacer()
            }

        }
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
                    isExpanded = !isExpanded
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
