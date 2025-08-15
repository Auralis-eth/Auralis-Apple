//
//  NewfeedCardView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import SwiftUI

struct NewsFeedCardView: View {
    let nft: NFT
    @State private var isExpanded: Bool = false

    @ViewBuilder
    private var imageView: some View {
        if let imageUrlString = nft.image?.originalUrl,
           !imageUrlString.isEmpty,
           let imageUrl = URL(string: imageUrlString) {
            CachedAsyncImage(url: imageUrl)
                .aspectRatio(contentMode: .fit)
                .clipped()
        } else {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                VStack {
                    Image(systemName: "photo")
                    if let imageUrlString = nft.image?.originalUrl,
                       !imageUrlString.isEmpty {
                        Text(imageUrlString)
                    }
                }
                    .foregroundStyle(Color.gray)
            }
            .aspectRatio(contentMode: .fit)
            .clipped()
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background NFT image
            imageView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            // Bottom content
            HStack(alignment: .lastTextBaseline) {
                if isExpanded {
                    ScrollView {
                        NewsFeedCardDetailsView(nft: nft, isExpanded: $isExpanded)
                            .glassEffect(.regular.tint(.surface),
                                         in: .rect(cornerRadius: 30, style: .continuous))
                            .safeAreaPadding(.leading, 15)
                    }
                    .defaultScrollAnchor(.top)
                } else {
                    NewsFeedCardDetailsView(nft: nft, isExpanded: $isExpanded)
                        .glassEffect(.regular.tint(.surface),
                                     in: .rect(cornerRadius: 30, style: .continuous))
                        .safeAreaPadding(.leading, 15)
                }

                Spacer()

                NewsFeedCardButtons()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

        }
    }
}


struct NewsFeedCardButtons: View {
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            VStack {
                Button(action: {}) {
                    ZStack {
                        Circle()
                            .stroke(Color.textPrimary, lineWidth: 2)
                            .frame(width: 25, height: 25)

                        // Profile image placeholder
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 20, height: 20)
                    }
                }

                Menu {
                    Button(action: {
                        // Copy ID action
                    }) {
                        Label("Copy ID", systemImage: "doc.on.doc")
                    }
                } label: {
                    SystemImage("ellipsis")
                        .foregroundStyle(Color.textPrimary)
                }

                Button(action: {
                    // Like action
                }) {
                    PrimaryTextSystemImage("heart")
                }

                Button(action: {
                    // Comment action
                }) {
                    PrimaryTextSystemImage("bubble.right")
                }

                Button(action: {
                    // Share action
                }) {
                    PrimaryTextSystemImage("paperplane")
                }

                Button(action: {
                    // Bookmark action
                }) {
                    PrimaryTextSystemImage("bookmark")
                }
            }
            .font(.title2)
            .padding()
            .buttonStyle(.glassProminent)
            .tint(Color.surface.opacity(0.8))
            .glassEffectUnion(id: "newsfeedcardbuttons", namespace: namespace)

        }
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

            if let contractAddress = nft.contract.address {
                OpenSeaLink(contractAddress: contractAddress, tokenId: nft.tokenId)
                EtherscanLink(contractAddress: contractAddress, tokenId: nft.tokenId)
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
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading) {
                HeadlineFontText(nft.collection?.name ?? "Unknown Collection")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                if let timeUpdated = nft.timeLastUpdated, let formattedDate = formattedDate(timeUpdated) {
                    HStack {
                        FootnoteFontText("Updated: ")
                        SecondaryCaptionFontText(formattedDate)
                    }
                }else {
                    FootnoteFontText("Updated: Not available")
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

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
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

    // Helper function to format date strings
    private func formattedDate(_ dateString: String) -> String? {
        // Create date formatter for ISO 8601 format
        let dateFormatter = Self.isoFormatter

        // Try to parse the date string
        guard let date = dateFormatter.date(from: dateString) else {
            return nil
        }

        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date, to: now)

        if let years = components.year, years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }

        if let months = components.month, months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }

        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }

        if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }

        if let seconds = components.second, seconds > 0 {
            return seconds == 1 ? "1 second ago" : "\(seconds) seconds ago"
        }

        return "Just now"
    }
}



//TODO:
//  1) replace overlay with Zstack





//  3) replace formatting code
// Use the modern, efficient, and localizable formatter
//private static let relativeFormatter = RelativeDateTimeFormatter()
//
//private var formattedUpdateTime: String {
//   guard let timeUpdated = nft.timeLastUpdated,
//         let date = ISO8601DateFormatter().date(from: timeUpdated) else {
//       return "Not available"
//   }
//   return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
//}
//----------------------------------------------------------
//private static let isoFormatters: [ISO8601DateFormatter] = {
//    var f1 = ISO8601DateFormatter()
//    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
//
//    var f2 = ISO8601DateFormatter()
//    f2.formatOptions = [.withInternetDateTime]
//
//    return [f1, f2]
//}()
//
//private static let relativeFormatter: RelativeDateTimeFormatter = {
//    let rf = RelativeDateTimeFormatter()
//    rf.unitsStyle = .short // or .full for accessibility
//    return rf
//}()
//
//private func parseISODate(_ s: String) -> Date? {
//    for f in Self.isoFormatters {
//        if let d = f.date(from: s) { return d }
//    }
//    return nil
//}
//
//private func formattedDate(_ dateString: String) -> String? {
//    guard let date = parseISODate(dateString) else { return nil }
//    // Clamp future dates to "Just now" or show "in X" depending on your product choice:
//    let now = Date()
//    if date > now { return Self.relativeFormatter.localizedString(fromTimeInterval: -1) } // "in 1 sec" -> adjust as desired
//    return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
//}
