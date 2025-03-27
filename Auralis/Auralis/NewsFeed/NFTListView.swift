//
//  NFTListView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI

import WebKit
struct BasicWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
}


struct NFTListView: View {
    @Binding var nftMetaData: [NFT]
    @Binding var selectedNFT: NFT?
    @State private var expandedAnimationNFT: NFT?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(nftMetaData) { metaData in
                    Card3D(cardColor: .surface) {
                        if let parsedmetaData = metaData.metadata {
                            VStack(alignment: .leading, spacing: 12) {
                                // NFT Name and Artist Info
                                Card3D(cardColor: .deepBlue.opacity(0.7)) {
                                    NFTNameView(
                                        name: parsedmetaData.name,
                                        arworkName: parsedmetaData.arworkName,
                                        metaCollectionName: parsedmetaData.collectionName,
                                        artist: parsedmetaData.artist,
                                        createdBy: parsedmetaData.createdBy
                                    )
                                }

                                // NFT Description
                                if let description = parsedmetaData.description, !description.isEmpty {
                                    NFTDescriptionView(description: description)
                                }

                                // NFT Image
                                // NFT Image with Animation Support
                                Card3D(cardColor: .deepBlue.opacity(0.5)) {
                                    ZStack {
                                        // Image display
                                        if expandedAnimationNFT?.id == metaData.id,
                                           let animationData = parsedmetaData.animationData {
                                            // Display animation when expanded
                                            NFTAnimationView(animation: animationData)
                                        } else {
                                            // Default image display
                                            NFTImageView(image: parsedmetaData.image ?? parsedmetaData.imageURL ?? parsedmetaData.imageData)
                                        }

                                        // Play button overlay
                                        if parsedmetaData.animationData != nil {
                                            VStack {
                                                Spacer()
                                                HStack {
                                                    Spacer()
                                                    Button(action: {
                                                        // Toggle animation view
                                                        if expandedAnimationNFT?.id == metaData.id {
                                                            expandedAnimationNFT = nil
                                                        } else {
                                                            expandedAnimationNFT = metaData
                                                        }
                                                    }) {
                                                        Circle()
                                                            .fill(Color.background.opacity(0.7))
                                                            .frame(width: 60, height: 60)
                                                            .overlay(
                                                                Image(systemName: expandedAnimationNFT?.id == metaData.id ? "stop.fill" : "play.fill")
                                                                    .resizable()
                                                                    .scaledToFit()
                                                                    .frame(width: 20, height: 20)
                                                                    .foregroundColor(.secondary)
                                                            )
                                                    }
                                                    .padding()
                                                }
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
                        } else {
                            // Fallback for NFTs without parsed metadata
                            VStack(spacing: 12) {
                                Text("NFT Details Unavailable")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)

                                Text("This NFT's metadata could not be parsed")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedNFT = metaData
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color.background)
    }
}
