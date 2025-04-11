//
//  NFTListView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftData
import SwiftUI


struct NFTListView: View {
    @Environment(\.modelContext) private var modelContext

    @Binding var mainAppStore: MainStore
    var nftFetcher = NFTFetcher()


    @Binding var selectedNFT: NFT?
    @State private var sortOrder = SortDescriptor(\NFT.acquiredAt?.blockTimestamp)
    @State private var searchText: String = ""

    var body: some View {
        VStack {
            NFTListingView(selectedNFT: $selectedNFT, sort: sortOrder, searchString: searchText, mainAppStore: $mainAppStore)
                .searchable(text: $searchText)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    //SORT options
                    Menu("Time", systemImage: "clock") {
//                        NFTSortButton(title: "Deployed", sortOrder: $sortOrder, keyPath: \.contract.deployedBlockNumber)
                        NFTSortButton(title: "Last Update", sortOrder: $sortOrder, keyPath: \.timeLastUpdated)
                        NFTSortButton(title: "Acquired", sortOrder: $sortOrder, keyPath: \.acquiredAt?.blockTimestamp)
                    }

//                    Button {
//                        //filter on Contract
//                        //          address
//                        //var tokenId: String
//                        //var contract: Contract
//                    } label: {
//                        Label("NFT", systemImage: "widget.large")
//                    }

//                    Button {
//                        //filter on Contract is spam
//                    } label: {
//                        Label("Spam", systemImage: "xmark.bin")
//                    }
                    NFTSortButton(title: "Collection Name", sortOrder: $sortOrder, keyPath: \.collection?.name)
                    NFTSortButton(title: "Item Name", sortOrder: $sortOrder, keyPath: \.name)
                } label: {
                    Image(systemName: "ellipsis")
                        .padding(8)
                }

                Button(action: {
                    Task {
                        await fetchAllNFTs()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    func fetchAllNFTs() async {
        do {
            let nfts = try await nftFetcher.fetchAllNFTs(for: mainAppStore.account, chain: mainAppStore.chain)
            //TODO: make this return the values/NFTs and save the data in the view
            //TODO go through the results and process and parse and update
            guard let nfts else {
                return
            }

            for nft in nfts {
                modelContext.insert(nft)
            }

            do {
                try modelContext.save()
            } catch {
                nftFetcher.error = error
            }

            let nftIDs = nfts.map(\.id)
            let descriptor = FetchDescriptor<NFT>(predicate: #Predicate { !nftIDs.contains($0.id) })
            do {
                try modelContext.enumerate(descriptor) { nft in
                    modelContext.delete(nft)
                }
                //                try modelContext.fetch(descriptor).forEach { nft in
                //                  modelContext.delete(nft)
                //                }
            } catch {
                print("Failed to retrieve NFTs to SwiftData: \(error)")
                nftFetcher.error = error
            }
        } catch {
            nftFetcher.error = error
        }

        nftFetcher.reset()

    }
}

struct NFTListingView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [
        SortDescriptor(\NFT.acquiredAt?.blockTimestamp),
        SortDescriptor(\NFT.collection?.name),
        SortDescriptor(\NFT.tokenId)
    ]) private var nfts: [NFT]

    @Binding var mainAppStore: MainStore
    @Binding var selectedNFT: NFT?
    @State private var expandedAnimationNFT: NFT?
    let searchString: String
    var nftFetcher = NFTFetcher()

    var displayNFTs: [NFT] {
        if searchString.trimmingCharacters(in: .whitespaces).isEmpty {
            nfts
        } else {
            nfts.filter {
                [$0.name, $0.collection?.name, $0.nftDescription]
                    .contains { field in
                        field?.localizedStandardContains(searchString) ?? false
                    }
            }
        }

    }
    var body: some View {
        if nfts.isEmpty {
            // No NFTs found view
            Card3D(cardColor: .surface) {
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
                            await fetchAllNFTs()
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
            }
            .padding(.horizontal, 40)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(displayNFTs) { metaData in
                        NFTNewsfeedPostView(nft: metaData)
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

    init(selectedNFT: Binding<NFT?>, sort: SortDescriptor<NFT>, searchString: String, mainAppStore: Binding<MainStore>) {
        _mainAppStore = mainAppStore
        _nfts = Query(sort: [sort])
        self.searchString = searchString
        _selectedNFT = selectedNFT
    }

    func fetchAllNFTs() async {
        do {
            let nfts = try await nftFetcher.fetchAllNFTs(for: mainAppStore.account, chain: mainAppStore.chain)
            //TODO: make this return the values/NFTs and save the data in the view
            //TODO go through the results and process and parse and update
            guard let nfts else {
                return
            }

            for nft in nfts {
                modelContext.insert(nft)
            }

            do {
                try modelContext.save()
            } catch {
                nftFetcher.error = error
            }

            let nftIDs = nfts.map(\.id)
            let descriptor = FetchDescriptor<NFT>(predicate: #Predicate { !nftIDs.contains($0.id) })
            do {
                try modelContext.enumerate(descriptor) { nft in
                    modelContext.delete(nft)
                }
                //                try modelContext.fetch(descriptor).forEach { nft in
                //                  modelContext.delete(nft)
                //                }
            } catch {
                print("Failed to retrieve NFTs to SwiftData: \(error)")
                nftFetcher.error = error
            }
        } catch {
            nftFetcher.error = error
        }

        nftFetcher.reset()

    }
}
