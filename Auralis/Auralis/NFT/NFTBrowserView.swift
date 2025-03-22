//
//  NFTBrowserView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI


struct NFTBrowserView: View {
    //TODO:
    //1) iterate over NFTS instead

    @State var nftMetaData: [WalletNFTResponse.NFT] = []
    @State var selectedNFT: WalletNFTResponse.NFT?
    @Binding var address: String
    @State var loading: Bool = false
    @State var error: Error?
    var body: some View {
        VStack {
            if let error = error as? Moralis.MoralisError {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Error")
                            .font(.headline)
                    }

                    switch error {
                    case .invalidData:
                        Text("Invalid data returned from server.")
                            .foregroundColor(.secondary)
                    case .invalidResponse:
                        Text("An unknown error occurred. Please check your connection and try again.")
                            .foregroundColor(.secondary)
                    }


                    Button {
                        Task {
                            // Add retry action here
                            await populateNFTs()
                        }
                    } label: {
                        Text("Try Again")
                            .fontWeight(.medium)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .padding(.top, 8)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
                .padding(.horizontal)
            } else if loading {
                ProgressView()
                    .padding()
                    .background(Color.white)
            }
            if address.isEmpty {
                Text("Please connect wallet")
                    .fontWeight(.medium)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            } else if nftMetaData.isEmpty {
                Text("No NFTs found")
                    .fontWeight(.medium)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            } else {
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
            ScrollView {
                //TODO: dispaly the values/properties of the nft
                VStack {
                    VStack(alignment: .leading) {
                        NFTNameView(
                            name: nft.parseMetadata?.name,
                            arworkName: nft.parseMetadata?.arworkName,
                            metaCollectionName: nft.parseMetadata?.collectionName,
                            artist: nft.parseMetadata?.artist,
                            createdBy: nft.parseMetadata?.createdBy
                        )

                            Divider()
                            Divider()

                        if let parsedmetaData = nft.parseMetadata {
                            ScrollView {
                                if let description = parsedmetaData.description {
                                    Text(description)
                                }
                            }
                            .frame(height: 200)
                        }

                        }
                        .padding()
                        .border(Color.black)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 0)
                        .padding()
                    ScrollView {
                    Text(nft.metadata ?? "NO META")
                    }
                    .frame(height: 200)
                    Text(nft.media ?? "NO MEDIA")




                    //                let tokenAddress: String?
                    //                let tokenId: String?
                    //                let contractType: String?
                    //                let ownerOf: String?
                    //                let blockNumber: String?
                    //                let blockNumberMinted: String?
                    //                    let tokenUri: String?
                    //                    let metadata: String?
                    //                let normalizedMetadata: String?
                    //                    let media: String?
                    //                let amount: String
                    //                let name: String?
                    //                let symbol: String?
                    //                let tokenHash: String?
                    //                let rarityRank: Int?
                    //                let rarityLabel: String?
                    //                let rarityPercentage: Double?
                    //                let lastTokenUriSync: String?
                    //                let lastMetadataSync: String?
                    //                let possibleSpam: Bool?
                    //                let verifiedCollection: Bool?



                    Divider()
                    NFTAnimationView(animation: nft.parseMetadata?.animationData)
                    Divider()
                    switch nft.parseMetadata?.imageHR {
                        case .url(let uRL):
                            HStack {
                                AsyncImage(url: uRL)
                                VStack {
                                    Text("URL IMAGE:")
                                    Text(uRL.absoluteString)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let pasteboard = UIPasteboard.general
                                pasteboard.string = uRL.absoluteString
                            }
                        case .data(let data):
                            VStack {
                                Text("DATA IMAGE:" )
                                Text(String(data: data, encoding: .utf8) ?? "NO IMAGE DATA")
                            }

                        case nil:
                            Text("NO IMAGE")
                        case .svg(let svg):
                            SVGView(string: svg)
                    }

                }
                .padding()
            }
        }
    }

    func populateNFTs() async {
        guard !loading else { return }
        guard address.count == 42 else { return }
        guard address.hasPrefix("0x") else { return }
        loading = true

        var nftMetaData: [WalletNFTResponse.NFT]? = nil
        do {
            let nftResponse = try await Moralis().getNFTs(for: address, normalizeMetadata: true)?.result
            nftMetaData = nftResponse?.filter({ $0.metadata != nil })
        } catch {
            self.error = error
        }
//        .filter {
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
//            .filter({ $0.parseMetadata?.animationURL != nil})


        (nftMetaData ?? []).forEach { nft in
            print("============================")
            guard let metadata = nft.parseMetadata else {
                print("no parseMetaData for this nft \(nft)")
                return
            }



//            print("-----------ANIMATION----------------")
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
//



//            print("metadata: \(metadata)")
//            print("createdBy: \(metadata.createdBy)")
//            print("artistWebsite: \(metadata.artistWebsite)")


//            print("animations: \(metadata.animationData?.animations)")
//            print("details: \(metadata.animationData?.details)")
//            print("imageDetails: \(metadata.imageDetails ?? [:])")
        }
        //.map(\WalletNFTResponse.NFT.parseMetadata).compactMap({ $0 }) ?? []
//                    print(nftMetaData)
//        if let data = nftMetaData.first {
//            self.nftMetaData = [data]
//        } else {
            self.nftMetaData = nftMetaData ?? []
//        }
//        self.nftMetaData = nftMetaData
        loading = false
    }
}
