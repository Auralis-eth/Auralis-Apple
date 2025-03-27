//
//  NFTDetailView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/24/25.
//

import SwiftUI

struct NFTDetailView: View {
    let nft: NFT
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header with dismiss button
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.trailing)
                    }

                    // Main content
                    VStack(spacing: 24) {
                        // Title section
                        VStack(alignment: .leading) {
                            if let parsedMetadata = nft.metadata {
                                Card3D(cardColor: .deepBlue) {
                                    NFTNameView(
                                        name: parsedMetadata.name,
                                        arworkName: parsedMetadata.arworkName,
                                        metaCollectionName: parsedMetadata.collectionName,
                                        artist: parsedMetadata.artist,
                                        createdBy: parsedMetadata.createdBy
                                    )
                                }

                                // Animation/Image section
                                if let image = parsedMetadata.primaryAssetURL ?? parsedMetadata.imageHR ?? parsedMetadata.image ?? parsedMetadata.imageURL ?? parsedMetadata.imageData ?? parsedMetadata.previewAssetURL {
                                    Card3D(cardColor: .surface) {
                                        NFTImageView(image: image)
                                    }
                                }

                                if let audioUrl = parsedMetadata.audioUrl ?? parsedMetadata.audioURI ?? parsedMetadata.audio ?? parsedMetadata.losslessAudio, !audioUrl.isEmpty {
                                    NFTMusicPlayer(audioURL: audioUrl)
                                }

                                // Description section
                                if let description = parsedMetadata.description, !description.isEmpty {
                                    Card3D(cardColor: .surface) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Description")
                                                .font(.headline)
                                                .foregroundColor(.accent)

                                            Text(description)
                                                .foregroundColor(.textPrimary)
                                                .font(.system(size: 15, weight: .regular, design: .serif))
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }

                                // NFT Properties/Attributes
                                if !parsedMetadata.attributes.isEmpty {
                                    Card3D(cardColor: .deepBlue.opacity(0.5)) {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("Properties")
                                                .font(.headline)
                                                .foregroundColor(.accent)

                                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                                ForEach(parsedMetadata.attributes) { attribute in
                                                    VStack(alignment: .leading) {
                                                        Text(attribute.traitType)
                                                            .font(.caption)
                                                            .foregroundColor(.textSecondary)

                                                        Text(attribute.value)
                                                            .font(.subheadline)
                                                            .foregroundColor(.textPrimary)
                                                            .fontWeight(.medium)
                                                    }
                                                    .accessibilityElement(children: .combine)
                                                    .padding(10)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .background(Color.accent.opacity(0.2))
                                                    .cornerRadius(8)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }

                                // Technical Details
                                Card3D(cardColor: .surface) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Technical Details")
                                            .font(.headline)
                                            .foregroundColor(.accent)

                                        VStack(alignment: .leading, spacing: 8) {
                                            DetailRow(title: "Contract", value: nft.nftBaseData.tokenAddress ?? "Unknown")
                                            DetailRow(title: "Token ID", value: nft.nftBaseData.tokenId ?? parsedMetadata.identifier ?? "Unknown")
                                            DetailRow(title: "Token Standard", value: nft.nftBaseData.contractType ?? "Unknown")
                                            DetailRow(title: "Blockchain", value: "Ethereum")

                                            if let rarityRank = nft.nftBaseData.rarityRank {
                                                DetailRow(title: "Rarity Rank", value: "\(rarityRank)")
                                            }

                                            if let rarityLabel = nft.nftBaseData.rarityLabel {
                                                DetailRow(title: "Rarity", value: rarityLabel)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                if let address = nft.nftBaseData.tokenAddress, let tokenID = nft.nftBaseData.tokenId ?? parsedMetadata.identifier {
                                    Card3D(cardColor: .surface) {
                                        OpenSeaLink(contractAddress: address, tokenId: tokenID)
                                    }
                                }
                            } else {
                                Text("Metadata unavailable")
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .truncationMode(.middle)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
