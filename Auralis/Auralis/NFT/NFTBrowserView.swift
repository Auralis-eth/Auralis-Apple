//
//  NFTBrowserView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI


struct NFTBrowserView: View {
    @State var nftMetaData: [WalletNFTResponse.NFT] = []
    @State var selectedNFT: WalletNFTResponse.NFT?
    @Binding var address: String
    @State var loading: Bool = false
    @State var error: Error?

    var body: some View {
        ZStack {
            // Background
            Color.background
                .ignoresSafeArea()

            VStack {
                if let error = error as? Moralis.MoralisError {
                    // Error view with updated styling
                    Card3D(cardColor: .error.opacity(0.2)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.error)
                                Text("Error")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                            }

                            switch error {
                            case .invalidData:
                                Text("Invalid data returned from server.")
                                    .foregroundColor(.textSecondary)
                            case .invalidResponse:
                                Text("An unknown error occurred. Please check your connection and try again.")
                                    .foregroundColor(.textSecondary)
                            }

                            Button {
                                Task {
                                    await populateNFTs()
                                }
                            } label: {
                                Text("Try Again")
                                    .fontWeight(.medium)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(Color.secondary)
                                    .foregroundColor(.black)
                                    .cornerRadius(8)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                } else if loading {
                    // Loading view
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .secondary))

                        Text("Loading NFTs...")
                            .font(.headline)
                            .foregroundColor(.textSecondary)
                            .padding(.top, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if address.isEmpty {
                    // Empty wallet view
                    VStack(spacing: 20) {
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("Connect Your Wallet")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)

                        Text("Please connect your wallet to view your NFTs")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.textSecondary)

                        Button {
                            // Connect wallet action would go here
                        } label: {
                            Text("Connect Wallet")
                                .fontWeight(.medium)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .background(Color.secondary)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 40)
                } else if nftMetaData.isEmpty {
                    // No NFTs found view
                    VStack(spacing: 20) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 60))
                            .foregroundColor(.accent)

                        Text("No NFTs Found")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)

                        Text("We couldn't find any NFTs in this wallet address")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.textSecondary)

                        Button {
                            Task {
                                await populateNFTs()
                            }
                        } label: {
                            Text("Refresh")
                                .fontWeight(.medium)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                                .background(Color.secondary)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 40)
                } else {
                    // NFTs list view
                    NFTListView(nftMetaData: $nftMetaData, selectedNFT: $selectedNFT)
                }
            }
            .refreshable {
                await populateNFTs()
            }
            .onChange(of: address, initial: false) {
                Task {
                    await populateNFTs()
                }
            }
            .task {
                await populateNFTs()
            }
            .sheet(item: $selectedNFT) { nft in
                NFTDetailView(nft: nft)
            }
        }
    }

    func populateNFTs() async {
        guard !loading else { return }
        guard address.count == 42 else { return }
        guard address.hasPrefix("0x") else { return }
        loading = true
        error = nil

        var nftMetaData: [WalletNFTResponse.NFT]? = nil
        do {
            let nftResponse = try await Moralis().getNFTs(for: address, normalizeMetadata: true)?.result
            nftMetaData = nftResponse?.filter({ $0.metadata != nil })
//                .filter {
               //            $0.parseMetadata?.animationData != nil
               //            || $0.parseMetadata?.imageData != nil
               //            || $0.parseMetadata?.primaryAssetURL != nil
               //            || $0.parseMetadata?.previewAssetURL != nil
               //            || $0.parseMetadata?.imageHR != nil
               //            || (
               //                $0.parseMetadata?.image != nil
               //                || $0.parseMetadata?.imageURL != nil
               //            )
               //
               //
               //
               //
               //
               //
               //
               ////                $0.parseMetadata?.animationData == nil
               //
               ////                $0.parseMetadata?.animationData != nil
               //            }

//            (nftMetaData ?? []).forEach { nft in
//                print("============================")
//                guard let metadata = nft.parseMetadata else {
//                    print("no parseMetaData for this nft \(nft)")
//                    return
//                }
                //                print("-----------ANIMATION----------------")
                //            print(metadata.animationData)
                //
                //            print("-----------IMAGE-HighRes----------------")
                //            print(metadata.imageHR)
                //            print(metadata.primaryAssetURL)
                //
                //            print("-----------IMAGE-lowres----------------")
                //            print(metadata.previewAssetURL)
                //            print(metadata.imageData)
                //            print(metadata.image ?? metadata.imageURL)
//            }
        } catch {
            self.error = error
        }

        self.nftMetaData = nftMetaData ?? []
        loading = false
    }
}

// New NFT Detail View for the sheet presentation
struct NFTDetailView: View {
    let nft: WalletNFTResponse.NFT
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
                            if let parsedMetadata = nft.parseMetadata {
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
                                if parsedMetadata.animationData != nil {
                                    Card3D(cardColor: .surface) {
                                        NFTAnimationView(animation: parsedMetadata.animationData)
                                    }
                                } else {
                                    Card3D(cardColor: .surface) {
                                        switch parsedMetadata.imageHR {
                                            case .url(let url):
                                                CachedAsyncImage(url: url)
                                            case .data(let data):
                                                if let image = UIImage(data: data) {
                                                    Image(uiImage: image)
                                                        .resizable()
                                                        .scaledToFit()
                                                }
                                            case .svg(let svg):
                                                SVGView(string: svg)
                                            case nil:
                                                if let imageSource = parsedMetadata.image ?? parsedMetadata.imageURL ?? parsedMetadata.imageData {
                                                    NFTImageView(image: imageSource)
                                                } else {
                                                    ZStack {
                                                        Color.surface
                                                            .aspectRatio(1, contentMode: .fit)
                                                        Image(systemName: "photo")
                                                            .font(.largeTitle)
                                                            .foregroundColor(.textSecondary)
                                                    }
                                                }
                                        }
                                    }
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
                                            DetailRow(title: "Contract", value: nft.tokenAddress ?? "Unknown")
                                            DetailRow(title: "Token ID", value: nft.tokenId ?? "Unknown")
                                            DetailRow(title: "Token Standard", value: nft.contractType ?? "Unknown")
                                            DetailRow(title: "Blockchain", value: "Ethereum")

                                            if let rarityRank = nft.rarityRank {
                                                DetailRow(title: "Rarity Rank", value: "\(rarityRank)")
                                            }

                                            if let rarityLabel = nft.rarityLabel {
                                                DetailRow(title: "Rarity", value: rarityLabel)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)
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
    }
}
