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
    @State private var currentAccount: EOAccount?
    @State private var currentChain: Chain = .ethMainnet
    @Query private var accounts: [EOAccount]
    
    @Environment(\.modelContext) private var modelContext
    @State private var nftService = NFTService()
    @StateObject private var audioEngine: AudioEngine
    
    @State private var isloading: Bool = false

    var nftsAreLoading: Bool {
        nftService.isLoading || isloading
    }


    var body: some View {
        Group {
            if !nftsAreLoading, currentAccount != .none {
                MainTabView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    currentChainId: $currentChainId,
                    currentChain: $currentChain,
                    nftService: $nftService,
                    audioEngine: audioEngine
                )
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        // Wrap the accessory in a container so it gets proper padding and material.
                        MiniPlayerView(audioEngine: audioEngine)
                    }
            } else if nftsAreLoading {
                NFTNewsfeedLoadingView(
                    itemsLoaded: nftService.itemsLoaded,
                    total: nftService.total
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
                .background {
                    GatewayBackgroundImage()
                        .ignoresSafeArea()

                    Color.background.opacity(0.3)
                        .ignoresSafeArea()
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
    
    init() {
        do {
            let engine = try AudioEngine()
            _audioEngine = StateObject(wrappedValue: engine)
        } catch {
            // Fallback for initialization errors
            fatalError("Failed to initialize AudioEngine: \(error)")
        }
    }
}
