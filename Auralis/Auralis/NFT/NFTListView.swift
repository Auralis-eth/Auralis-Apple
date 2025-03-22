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
    @Binding var nftMetaData: [WalletNFTResponse.NFT]
    @Binding var selectedNFT: WalletNFTResponse.NFT?

    var body: some View {
        LazyVStack {
            ForEach(nftMetaData) { metaData in
                Card3D() {

                    if let parsedmetaData = metaData.parseMetadata {
                        VStack(alignment: .leading) {
                            Card3D(cardColor: .white) {
                                NFTNameView(
                                    name: parsedmetaData.name,
                                    arworkName: parsedmetaData.arworkName,
                                    metaCollectionName: parsedmetaData.collectionName,
                                    artist: parsedmetaData.artist,
                                    createdBy: parsedmetaData.createdBy
                                )
                            }

                            if let description = parsedmetaData.description, !description.isEmpty {
                                NFFTDescriptionView(description: description)
                            }
                            Card3D(cardColor: .white) {
                                NFTImageView(image: parsedmetaData.image ?? parsedmetaData.imageURL ?? parsedmetaData.imageData)
                                    .overlay(
                                        ZStack {
                                            // Play button overlay
                                            if parsedmetaData.animationData != nil {
                                                Circle()
                                                    .fill(Color.black.opacity(0.5))
                                                    .frame(width: 60, height: 60)

                                                Image(systemName: "play.fill")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 20, height: 20)
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    )
                            }
                            //Category
                            VStack {
                                Text("Category")
                                Text("Category Selector")
                            }
                        }
                        //create static instagram card
                        //  Post component
                        //  Post Engagement
                        //  Post Detail
                        //  Post Permissions
                        //  Edit Post
                        //  Rwaction/share

                        //  Text Post
                        //  Image
                        //  Video
                        //  File

                        //User profile
                        //search

                        //Redo each one using Dviances






















                    }
                    //TODO:
                    //        - Add a button to view the NFT in a detailed view
                    //        - move data extraction up to view model or network processing
                    //      create the UI cards
                    //      work on cleaning up code

                    //      print("-----------ANIMATION----------------")
                    //      print(metadata.animationData)
                    //                NFTAnimationView
                    //
                    //      print("-----------IMAGE-HighRes----------------")
                    //      print(metadata.imageHR)
                    //      print(metadata.primaryAssetURL)
                    //
                    //      print("-----------IMAGE-lowres----------------")
                    //      print(metadata.previewAssetURL)
                    //      print(metadata.imageData)
                    //      print(metadata.image ?? metadata.imageURL)

                    //      clean up UI
                    //      work on debugging media that does not load
                    //      expand Networking
                    //          chain: String = "eth",
                    //          format: String? = "decimal",
                    //          limit: Int? = nil,
                    //          excludeSpam: Bool? = nil,
                    //          cursor: String? = nil
                    //          mediaItems: Bool? = nil
                    //====================================================================================
                    //====================================================================================
                    //  A) finish ALL keys/properties
                    //attributes
                    //====================================================================================
                    //====================================================================================
                    //====================================================================================
                    //====================================================================================
                    //====================================================================================
                    //  B) go through other accounts and repeat
                    //    A) get uncollected/processed keys
                    //    1. Get keys
                    //    2. Go through each key and get possible values
                    //    3. Group keys into related
                    //    4. Create UI element for group or key
                    //    5. Repeat for each address

                    //    B) verify each key works/find bugs
                    //====================================================================================
                    //  C) create a combined accounts NFT list to further refine the general app
                    //====================================================================================
                    //  TODO: Expanded support
                    //  1) SVG
                    //  2) 3D
                    //      A)  model_usdz: URL for a USDZ (3D model) file.
                    //      B)  vrm_url: URL for a VRM (3D avatar) model.
                    //              glTF 2.0
                    //      C)  model_glb: URL for a GLB (3D model) file.
                    //              binary file format for glTF 2.0
                    //  3) IPFS
                    //  4) ARWEAVE
                    //  5) Etherscan
                    //  6) ENS
                    //  7) generator.artblocks.io

                    //  TODO: next iteration, expanded features etc
                    //  1) in full Screen NFT view show the image and animation details properties info
                    //      A) need a way to show primaryAssetURL
                    //====================================================================================

                }
                .padding(.horizontal, 16)
                .padding()
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedNFT = metaData
                }
            }
        }
    }
}
