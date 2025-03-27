//
//  NFTBrowserView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI


struct NFTBrowserView: View {
    @Binding var mainAppStore: MainStore
    @State private var selectedNFT: NFT?

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                if let error = mainAppStore.error as? Moralis.MoralisError {
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
                                    await mainAppStore.fetchAllNFTs()
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
                } else if mainAppStore.loading {
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
                } else if mainAppStore.account.isEmpty {
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
                } else if mainAppStore.nftMetaData.isEmpty {
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
                                await mainAppStore.fetchAllNFTs()
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
                    NFTListView(nftMetaData: $mainAppStore.nftMetaData, selectedNFT: $selectedNFT)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.background)
        }
        .background(Color.background)
        .refreshable {
            await mainAppStore.fetchAllNFTs()
        }
        .onChange(of: mainAppStore.account, initial: false) {
            Task {
                await mainAppStore.fetchAllNFTs()
            }
        }
        .task {
            await mainAppStore.fetchAllNFTs()
        }
        .sheet(item: $selectedNFT) { nft in
            NFTDetailView(nft: nft)
        }
    }

    
}
