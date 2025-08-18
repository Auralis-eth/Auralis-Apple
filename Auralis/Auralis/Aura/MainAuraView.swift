//
//  MainAuraView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI
import SwiftData

//    var account: EOAccount? //= EOAccount(address: "0x5b93ff82faaf241c15997ea3975419dddd8362c5", access: .readonly)
struct MainAuraView: View {
    @AppStorage("currentAccountAddress") var currentAddress: String = ""
    @AppStorage("currentChainId") var currentChainId: String = Chain.ethMainnet.rawValue
    @Environment(\.modelContext) private var modelContext
    @State private var nftService = NFTService()

    @State private var currentAccount: EOAccount?
    @State private var currentChain: Chain = .ethMainnet

    @Query private var accounts: [EOAccount]

    @Namespace private var namespace
    private let transitionID = "transition-id"
    @State private var isPresented: Bool = false
    @State private var isloading: Bool = false
    @State private var presentDialog: Bool = false

    var nftsAreLoading: Bool {
        nftService.isLoading || isloading
    }

    var tabView: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                VStack {
                    Text("HELLO \(currentAccount?.address ?? "")")
                    Button("Logout") {
                        try? modelContext.delete(model: NFT.self)
                        try? modelContext.delete(model: EOAccount.self)
                        self.currentAccount = nil
                        currentAddress = ""
                        currentChainId = ""
                    }
                }
                .sheet(isPresented: $isPresented) {
                    Button(action: {
                        presentDialog = true
                    }, label: {
                        Text("hello")
                    })
                    .confirmationDialog("Delete?", isPresented: $presentDialog) {
                        Text("not deleted")
                    }
                    .navigationTransition(.zoom(sourceID: transitionID, in: namespace))

                }
            }

            Tab("NewsFeed", systemImage: "bubble.right") {
                NewsFeedView(currentAccount: $currentAccount, nftService: $nftService, currentChain: $currentChain)
            }

            Tab("Gas", systemImage: "fuelpump") {
                ZStack(alignment: .bottom) {
                    GatewayBackgroundImage()
                    Color.background.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                    GasPriceEstimateView(chain: $currentChain)
                }
            }
            
            Tab("Music", systemImage: "play.circle") {
                MusicPlayerView()
            }

            Tab("Profile", systemImage: "person.circle") {
                Text("SentView()")
                Text("ENS")
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textPrimary)
                        .font(.headline)
                }

            }
        }
        .tint(.accent)
    }

    var body: some View {
        Group {
            if !nftsAreLoading, let currentAccount {
                tabView
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        if 0 > 9 {
                            Text("Hello")
                        }
                    }
            } else if nftsAreLoading {
                ZStack(alignment: .bottom) {
                    GatewayBackgroundImage()
                    Color.background.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                    NFTNewsfeedLoadingView(
                        itemsLoaded: nftService.itemsLoaded,
                        total: nftService.total
                    )
                }

                
            } else {
                GatewayView(currentAccount: $currentAccount)
            }
        }
        .onAppear {
            currentChain = Chain(rawValue: currentChainId) ?? .ethMainnet

            guard !currentAddress.isEmpty else {
                currentAccount = nil
                return
            }

            let fetchResult = accounts.filter { $0.address == currentAddress }
            if let first = fetchResult.first {
                currentAccount = first
            } else {
                let account = EOAccount(address: currentAddress)
                currentAccount = account
            }
        }
        .onChange(of: currentAccount) { oldValue, newValue in
            if currentAccount?.address != currentAddress, currentAccount != nil {
                isloading = true
                Task {
                    await nftService.refreshNFTs(for: currentAccount, chain: currentChain, modelContext: modelContext)
                    await MainActor.run {
                        isloading = false
                    }
                }
            }

            currentAddress = newValue?.address ?? ""
        }
        .onChange(of: currentChain) { oldValue, newValue in
            currentChainId = newValue.rawValue
        }
        .onChange(of: currentAddress) { oldValue, newValue in
            guard !newValue.isEmpty else {
                currentAccount = nil
                return
            }
            let fetchResult = accounts.filter { $0.address == newValue }
            if let first = fetchResult.first {
                currentAccount = first
            } else {
                let account = EOAccount(address: currentAddress)
                currentAccount = account
            }
        }
    }

}
//
//import ImagePlayground
//@available(iOS 18.4, *)
//func generateImageFromPlayground() async throws {
//    let seletedStyle: ImagePlaygroundStyle = .animation
//    let creator = try await ImageCreator()
//    let images = creator.images(for: [.text("Aurora Borealis over the Arctic and Rocky Mounts")], style: seletedStyle, limit: 4)
//
//    for try await image in images {
//        print("Generated image:")
//        print(image.cgImage)
//    }
//}
//
//// TIPS
////      Break down the process/request
//
////  USE CASES
////      Content Generation???
////          splash image
////      summarization
////          in the NFT newsfeed view summarize NFT text blurb
////      In-app  user guides
////          have a ? button on each screen and do a help bot
////      Classification
////          start with the "stash" page for NFTs, then migrate to ERC-20s
////      Tag generation
////          start with the "stash" page for NFTs, then migrate to ERC-20s
//
//
////      Composition???
////          what is it and could I use it
////      Revision???
////          what is it and could I use it
