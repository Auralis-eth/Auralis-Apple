//
//  NewfeedCardView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import SwiftUI

struct NewfeedCardView: View {
    let nft: NFT
    @State private var isExpanded: Bool = false
    var buttons: some View {
        VStack(spacing: 12) {
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
                    .font(.title2)
            }


            Button(action: {
                // Like action
            }) {
                PrimaryTextSystemImage("heart")
                    .font(.title2)
            }

            Button(action: {
                // Comment action
            }) {
                PrimaryTextSystemImage("bubble.right")
                    .font(.title2)
            }

            Button(action: {
                // Share action
            }) {
                PrimaryTextSystemImage("paperplane")
                    .font(.title2)
            }

            Button(action: {
                // Bookmark action
            }) {
                PrimaryTextSystemImage("bookmark")
                    .font(.title2)
            }

        }
        .padding()
    }

    var cardDetailsExpandedDetails: some View {
        // NFT details
        VStack(alignment: .leading, spacing: 8) {
            // Title and description
            SystemFontText(text: nft.name ?? "Unnamed NFT", size: 18, weight: .semibold)

            VStack {
                // Token details
                HeadlineFontText("Technical Details")
                DetailRow(title: "Contract", value: nft.contract.address ?? "0x0")
                DetailRow(title: "Token ID", value: nft.tokenId)
                DetailRow(title: "Token Standard", value: nft.tokenType ?? "Unknown")
                DetailRow(title: "Blockchain", value: nft.network?.networkName ?? "Unknown")
            }

            // Attributes/Traits section
            if let metadata = nft.raw?.metadata, let attributes = metadata.attributes, !attributes.isEmpty {
                HeadlineFontText("Traits")
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attributes, id: \.traitType) { attribute in
                            VStack(alignment: .center) {
                                if let traitType = attribute.traitType {
                                    SecondaryCaptionFontText(traitType)
                                }

                                Caption2FontText(attribute.value)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
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
    var cardDetailsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading) {
                Text(nft.collection?.name ?? "Unknown Collection")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                if let timeUpdated = nft.timeLastUpdated {
                    HStack {
                        FootnoteFontText("Updated: ")
                        SecondaryCaptionFontText(formattedDate(timeUpdated))
                    }
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
                .contentShape(Rectangle())
                .onTapGesture {
                    isExpanded = !isExpanded
                }
            }

            if isExpanded {
                cardDetailsExpandedDetails
                    .padding(.top)
            }
        }
        .padding()
    }
    var body: some View {
        // NFT image
        Group {
            if let imageUrlString = nft.image?.originalUrl, !imageUrlString.isEmpty, let imageUrl = URL(string: imageUrlString) {
                CachedAsyncImage(url: imageUrl)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        SystemImage("photo")
                            .foregroundStyle(Color.gray)
                    )
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
                // Bottom content
            HStack(alignment: .bottom) {
                ScrollView {
                    cardDetailsView
                        .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: 30, style: .continuous))
                        .safeAreaPadding(.leading, 15)
                }
                .defaultScrollAnchor((isExpanded && (nft.nftDescription?.count ?? 0) > 1000) ? .top : .bottom)

                Spacer()

                GlassEffectContainer(spacing: 12) {
                    buttons
                        .glassEffect(.regular.tint(.surface), in: .capsule)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .background(Color.surface.opacity(0.5))
        }
    }


    // Helper function to format date strings
    private func formattedDate(_ dateString: String) -> String {
        // Convert the API date string to a readable format
        // This is a simple placeholder - you'll need to adapt this to your actual date format
        timeAgoSince(dateString: dateString)
    }

    func timeAgoSince(dateString: String) -> String {
        // Create date formatter for ISO 8601 format
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Try to parse the date string
        guard let date = dateFormatter.date(from: dateString) else {
            return "Invalid date format"
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

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            SubheadlineFontText(title)
                .frame(width: 100, alignment: .leading)

            SubheadlineFontText(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}
