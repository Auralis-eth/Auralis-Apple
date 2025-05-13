//
//  MainView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/23/25.
//

import SwiftUI

//TODO:
//SwiftLint install
//========================================================================
//========================================================================
//    func createClient() async throws {
//        guard let clientUrl = URL(string: "https://an-infura-or-similar-url.com/123") else { return }
//        let client = EthereumHttpClient(url: clientUrl, network: .mainnet)
//
//    //    guard let clientUrl = URL(string: "wss://sepolia.infura.io/ws/v3//123") else { return }
//    //    let client = EthereumWebSocketClient(url: clientUrl, network: .mainnet)
//
//        client.eth_gasPrice { currentPrice in
//            print("The current gas price is \(currentPrice)")
//        }
//
//        let gasPrice = try await client.eth_gasPrice()
//
//    }
//}
//
//===================================================================================================================================================
//================================================================================================

//===================================================================================================================================================
//================================================================================================
import SwiftData
struct MainView: View {
    @State private var mainAppStore = MainStore()
    @AppStorage("currentAccountAddress") var currentAddress: String = ""
    @AppStorage("currentChainId") var currentChainId: String = Chain.ethMainnet.rawValue
    @Environment(\.modelContext) private var modelContext
    @State private var currentAccount: EOAccount?
    @State private var currentChain: Chain?

    @State private var chaining: Chain = .ethMainnet

    @Query private var accounts: [EOAccount]

    var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    func points(for timeline: TimelineViewDefaultContext) -> [SIMD2<Float>] {
        [
            // First row
            [0, 0], [0.2, 0], [0.4, 0], [0.6, 0], [0.8, 0], [1, 0],

            // Second row
            [0, 0.2],
            [0.2, Float(0.2 + 0.05 * sin(timeline.date.timeIntervalSince1970 * 0.5))],
            [0.4, Float(0.2 + 0.08 * sin(timeline.date.timeIntervalSince1970 * 0.7 + 0.5))],
            [0.6, Float(0.2 + 0.06 * sin(timeline.date.timeIntervalSince1970 * 0.6 + 1.0))],
            [0.8, Float(0.2 + 0.04 * sin(timeline.date.timeIntervalSince1970 * 0.8 + 1.5))],
            [1, 0.2],

            // Third row - Main aurora activity
            [0, 0.4],
            [0.2, Float(0.4 + 0.12 * sin(timeline.date.timeIntervalSince1970 * 0.8 + 0.2))],
            [0.4, Float(0.4 + 0.15 * sin(timeline.date.timeIntervalSince1970 * 0.9 + 0.7))],
            [0.6, Float(0.4 + 0.18 * sin(timeline.date.timeIntervalSince1970 * 1.0 + 1.3))],
            [0.8, Float(0.4 + 0.14 * sin(timeline.date.timeIntervalSince1970 * 0.7 + 1.8))],
            [1, 0.4],

            // Fourth row - Main aurora activity
            [0, 0.6],
            [0.2, Float(0.6 + 0.13 * sin(timeline.date.timeIntervalSince1970 * 0.9 + 0.3))],
            [0.4, Float(0.6 + 0.17 * sin(timeline.date.timeIntervalSince1970 * 1.1 + 0.8))],
            [0.6, Float(0.6 + 0.19 * sin(timeline.date.timeIntervalSince1970 * 0.9 + 1.4))],
            [0.8, Float(0.6 + 0.15 * sin(timeline.date.timeIntervalSince1970 * 0.8 + 1.9))],
            [1, 0.6],

            // Fifth row
            [0, 0.8],
            [0.2, Float(0.8 + 0.06 * sin(timeline.date.timeIntervalSince1970 * 0.7 + 0.4))],
            [0.4, Float(0.8 + 0.09 * sin(timeline.date.timeIntervalSince1970 * 0.6 + 0.9))],
            [0.6, Float(0.8 + 0.07 * sin(timeline.date.timeIntervalSince1970 * 0.8 + 1.5))],
            [0.8, Float(0.8 + 0.05 * sin(timeline.date.timeIntervalSince1970 * 0.7 + 2.0))],
            [1, 0.8],

            // Sixth row
            [0, 1], [0.2, 1], [0.4, 1], [0.6, 1], [0.8, 1], [1, 1]
        ]
    }
    func colorsForNorthernLights() -> [Color] {
        [
            // First row (night sky background)
            .background, .background, .background, .background, .background, .background,

            // Second row (subtle stars and beginning aurora)
            .surface,
            .secondary,
            .accent,
            .deepBlue,
            .secondary,
            .surface,

            // Third row (main aurora colors - greens)
            .secondary,
            .secondary,
            .secondary,
            .deepBlue,
            .secondary,
            .secondary,

            //  Fourth row
            .secondary,
            .accent,
            .deepBlue,
            .accent,
            .secondary,
            .surface,


            // Fifth row (fading aurora)
            .secondary,
            .accent,
            .deepBlue,
            .accent,
            .secondary,
            .surface,

            // Sixth row (night sky background)
            .background, .background, .background, .background, .background, .background
        ]
    }
    func northernLights(in geometry: GeometryProxy) -> some View {
        TimelineView(.animation) { timeline in
            MeshGradient(
                width: 6,  // Increased from 3 to 6 for more detail
                height: 6, // Increased from 3 to 6 for more detail
                points: points(for: timeline),
                colors: colorsForNorthernLights(),
                background: .black
            )
            .frame(maxWidth: .infinity, minHeight: geometry.frame(in: .local).height)
        }
    }
    var body: some View {
        Group {
            if isIpad {
//                ScrollView {
//                    VStack {
                        GeometryReader { geometry in
                            northernLights(in: geometry)
                                .overlay(.ultraThinMaterial)
                        }

                        //                    HStack {
                        //                        Spacer()
                        //                        ImportWalletView(address: $currentAccount)
                        //                        Spacer()
                        //                    }
                        //                    HStack {
                        //                        MainVIewEmptyAddress(account: $currentAccount)
                        //                        WalletView(account: $currentAccount, chainId: $chaining)
                        //                    }
//                    }
//                }
            } else if currentAccount != nil {
                TabView {
                    Text("HOME")
                        .tabItem {
                            SystemImage("house")
                            Text("Home")
                        }

                    WalletView(account: $currentAccount, chainId: $mainAppStore.chain)
                        .tabItem {
                            SystemImage("wallet.bifold.fill")
                            Text("Wallet")
                        }

                    NFTBrowserView(mainAppStore: $mainAppStore, currentAccount: $currentAccount)
                        .tabItem {
                            SystemImage("location.north.circle")
                            Text("NFT Browser")
                        }

                    GasPriceEstimateView(chain: $mainAppStore.chain)
                        .tabItem {
                            SystemImage("fuelpump")
                            Text("Gas")
                        }

                    //            MusicApp(musicNFTs: mainAppStore.musicNFTs)
                    //                .tabItem {
                    //                    SystemImage("music.quarternote.3")
                    //                    Text("Music")
                    //                }
                }
            } else {
                MainVIewEmptyAddress(account: $currentAccount)
            }
        }
        .tint(Color.accent)
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

