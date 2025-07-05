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
                            SecondaryTextSystemImage("xmark.circle.fill")
                                .font(.title2)
                        }
                        .padding(.trailing)
                    }

                    // Main content
                    VStack(spacing: 24) {
                        // Title section
                        VStack(alignment: .leading) {
                            Card3D(cardColor: .surface) {
                                VStack(alignment: .leading, spacing: 16) {
                                    // Header with collection name and date

                                    HStack {
                                        VStack(alignment: .leading) {
                                            SystemFontText(
                                                text: nft.collection?.name ?? "Unknown Collection",
                                                size: 14,
                                                weight: .medium
                                            )

                                            if let timeUpdated = nft.timeLastUpdated {
                                                HStack {
                                                    FootnoteFontText("Updated: ")
                                                    SecondaryCaptionFontText(timeUpdated)
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
                                            SystemImage("ellipsis")
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
                                                    SystemImage("photo")
                                                        .foregroundStyle(Color.gray)
                                                )
                                        }
                                    }
                                    .cornerRadius(0)                                    

                                    // NFT details
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Title and description
                                        SystemFontText(
                                            text: nft.name ?? "Unnamed NFT",
                                            size: 18,
                                            weight: .semibold
                                        )

                                        // NFT Description
                                        if let description = nft.nftDescription, !description.isEmpty {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HeadlineFontText("Description")

                                                SystemFontText(text: description, size: 15, weight: .regular)
                                            }
                                            .padding(.vertical, 8)
                                        }

                                        // Token details
                                        VStack {
                                            HeadlineFontText("Technical Details")
                                            DetailRow(title: "Contract", value: nft.contract.address ?? "0x0")
                                            DetailRow(title: "Token ID", value: nft.tokenId)
                                            DetailRow(title: "Token Standard", value: nft.tokenType ?? "Unknown")
                                            DetailRow(title: "Blockchain", value: nft.network?.networkName ?? "Unknown")
                                        }
                                        if let contractAddress = nft.contract.address {
                                            Card3D(cardColor: .surface) {
                                                OpenSeaLink(contractAddress: contractAddress, tokenId: nft.tokenId)
                                                EtherscanLink(contractAddress: contractAddress, tokenId: nft.tokenId)
                                            }
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

                                        // Category display (placeholder)
                                        HStack {
                                            Spacer()
                                            Text("Category")
                                            PrimaryCaptionFontText("Category Selector")
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.accent.opacity(0.3))
                                                .cornerRadius(16)
                                            Spacer()
                                        }

                                    }
                                    .padding(.horizontal)
                                }
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
            SubheadlineFontText(title)
                .frame(width: 100, alignment: .leading)

            SubheadlineFontText(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }
}
