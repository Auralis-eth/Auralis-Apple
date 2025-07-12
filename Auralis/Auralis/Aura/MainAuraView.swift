//
//  MainAuraView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI
import SwiftData

struct MainAuraView: View {
    @State private var mainAppStore = MainStore()
    @AppStorage("currentAccountAddress") var currentAddress: String = ""
    @AppStorage("currentChainId") var currentChainId: String = Chain.ethMainnet.rawValue
    @Environment(\.modelContext) private var modelContext
    @State private var currentAccount: EOAccount?
    @State private var currentChain: Chain = .ethMainnet

    @State private var chaining: Chain = .ethMainnet

    @Query private var accounts: [EOAccount]

    @Namespace private var namespace
    private let transitionID = "transition-id"
    @State private var isPresented: Bool = false
    @State private var presentDialog: Bool = false

    var tabView: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                VStack {
                    Text("HELLO \(currentAccount?.address ?? "")")
                    Button("Logout") {
                        do {
                            try modelContext.delete(model: NFT.self)
                            try modelContext.delete(model: EOAccount.self)
                            self.currentAccount = nil
                        } catch {

                        }
                    }
                    if let address = currentAccount?.address {
                        Button("Fetch") {
                            Task {
                                let nfts = try await NFTFetcher().fetchAllNFTs(for: address, chain: currentChain)
                                print(nfts)
                            }
                        }
                    }
                }
                .sheet(isPresented: $isPresented) {
                    if #available(iOS 26.0, *) {
                        Button(action: {
                            presentDialog = true
                        }, label: {
                            Text("hello")
                        })
                        .confirmationDialog("Delete?", isPresented: $presentDialog) {
                            Text("not deleted")
                        }
                            .navigationTransition(.zoom(sourceID: transitionID, in: namespace))
                    }  else {
                        Text("NO SHEET")
                    }
                }
            }

            Tab("NewsFeed", systemImage: "bubble.right") {
                NewsFeedView(currentAccount: $currentAccount, currentChain: $currentChain)
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
            if let currentAccount {
                if #available(iOS 26.0, *) {
                    tabView
                        .tabBarMinimizeBehavior(.onScrollDown)
//                        .tabViewBottomAccessory {
//                            if 0 > 9 {
//                                Text("Hello")
//                            }
//                        }
                } else {
                    tabView
                }
            } else {
                LoginView(currentAccount: $currentAccount)
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
            currentAddress = newValue?.address ?? ""
        }
        .onChange(of: mainAppStore.chain) { oldValue, newValue in
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
