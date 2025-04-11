//
//  NFTNewsfeedPostView.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//


import SwiftUI
import SwiftData

// Detail view that appears when an NFT is tapped
struct NFTNewsfeedPostView: View {
    let nft: NFT

    var body: some View {
        Card3D(cardColor: .surface) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with collection name and date

                HStack {
                    VStack(alignment: .leading) {
                        Text(nft.collection?.name ?? "Unknown Collection")
                            .font(.system(size: 14, weight: .medium, design: .serif))
                            .foregroundColor(.textSecondary)

                        if let timeUpdated = nft.timeLastUpdated {
                            HStack {
                                Text("Updated: ")
                                    .font(.footnote)
                                    .foregroundColor(.textSecondary)
                                Text(formattedDate(timeUpdated))
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }

                    Spacer()

                    Menu {
                        Button(action: {
                            // Copy ID action
                        }) {
                            Label("Copy ID", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .padding(8)
                    }
                }

                // NFT image
                Group {
                    if let imageUrlString = nft.image?.originalUrl, !imageUrlString.isEmpty, let imageUrl = URL(string: imageUrlString) {
                        CachedAsyncImage(url: imageUrl)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            )
                    }
                }
                .cornerRadius(0)

                // Interaction buttons (like Instagram)
                HStack(spacing: 16) {
                    Button(action: {
                        // Like action
                    }) {
                        Image(systemName: "heart")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }

                    Button(action: {
                        // Comment action
                    }) {
                        Image(systemName: "bubble.right")
                            .font(.title2)
                            .foregroundColor(.accent)
                    }

                    Button(action: {
                        // Share action
                    }) {
                        Image(systemName: "paperplane")
                            .font(.title2)
                            .foregroundColor(.textPrimary)
                    }

                    Spacer()

                    Button(action: {
                        // Bookmark action
                    }) {
                        Image(systemName: "bookmark")
                            .font(.title2)
                            .foregroundColor(.deepBlue)
                    }
                }
                .padding(.horizontal)
//                .foregroundColor(.deepBlue)

                // NFT details
                VStack(alignment: .leading, spacing: 8) {
                    // Title and description
                    Text(nft.name ?? "Unnamed NFT")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundColor(.textPrimary)

                    // NFT Description
                    if let description = nft.nftDescription, !description.isEmpty {
                        NFTDescriptionView(description: description)
                    }

                    // Token details
                    HStack {
                        Text("Token ID:")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text(nft.tokenId)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.textPrimary)
                    }

                    HStack {
                        Text("Contract:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .foregroundColor(.textSecondary)
                        Text(nft.contract.address ?? "0x0")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.textPrimary)
                    }

                    // Attributes/Traits section
                    if let metadata = nft.raw?.metadata, let attributes = metadata.attributes, !attributes.isEmpty {
                        Text("Traits")
                            .font(.headline)
                            .padding(.top, 8)
                            .foregroundColor(.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(attributes, id: \.traitType) { attribute in
                                    VStack(alignment: .center) {
                                        if let traitType = attribute.traitType {
                                            Text(traitType)
                                                .font(.caption)
                                                .foregroundColor(.textSecondary)
                                        }

                                        Text(attribute.value)
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.textPrimary)
                                    }
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }

                    // Category display (placeholder)
                    HStack {
                        Spacer()
                        Text("Category")
                        Text("Category Selector")
//                                    Text(parsedmetaData.category ?? "Collectible")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accent.opacity(0.3))
                            .foregroundColor(.textPrimary)
                            .cornerRadius(16)
                        Spacer()
                    }

                }
                .padding(.horizontal)
            }
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
