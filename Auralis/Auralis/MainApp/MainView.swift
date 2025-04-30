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

    @Query private var accounts: [EOAccount]

    var body: some View {
        Group {
            if let currentAccount {
                TabView {
                    WalletView(account: $mainAppStore.account, chainId: $mainAppStore.chain)
                        .tabItem {
                            Image(systemName: "wallet.bifold.fill")
                            Text("Wallet")
                        }

                    NFTBrowserView(mainAppStore: $mainAppStore)
                        .tabItem {
                            Image(systemName: "location.north.circle")
                            Text("NFT Browser")
                        }

                    GasPriceEstimateView(chain: $mainAppStore.chain)
                        .tabItem {
                            Image(systemName: "fuelpump")
                            Text("Gas")
                        }

                    //            MusicApp(musicNFTs: mainAppStore.musicNFTs)
                    //                .tabItem {
                    //                    Image(systemName: "music.quarternote.3")
                    //                    Text("Music")
                    //                }
                }
            } else {

                //TODO: cleanup/finish onAppear
                MainVIewEmptyAddress(account: $mainAppStore.account)

            }
        }
        .tint(Color.accent)
        .constructionBorder(animate: true)
        .onAppear {
            currentChain = Chain(rawValue: currentChainId) ?? .ethMainnet

            guard !currentAddress.isEmpty else { return }

            let fetchResult = accounts.filter { $0.address == currentAddress }
            if let first = fetchResult.first {
                currentAccount = first
            } else {
                let account = EOAccount(address: currentAddress, access: .readonly)
            }
        }
        .onChange(of: mainAppStore.account) { oldValue, newValue in
            currentAddress = newValue?.address ?? ""
            currentAccount = newValue
        }
        .onChange(of: mainAppStore.chain) { oldValue, newValue in
            currentChainId = newValue.rawValue
        }
    }
}


struct ConstructionTapeBorder: ViewModifier {
    let angle: Double
    let animate: Bool

    @State private var offset: CGFloat = 0

    init(angle: Double = 45, animate: Bool = true) {
        self.angle = angle
        self.animate = animate
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 40)
            .overlay(
                Rectangle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.black, .yellow]),
                            center: .center,
                            startAngle: .degrees(offset),
                            endAngle: .degrees(360.0 + offset)
                        ),
                        style: StrokeStyle(
                            lineWidth: 20,
                            lineCap: .butt,
                            lineJoin: .miter,
                            miterLimit: 1,
                            dash: [10, 10],
                            dashPhase: offset
                        )
                    )
                    .overlay {
                        VStack {
                            Text("UNDER CONSTRUCTION")
                                .foregroundStyle(Color.textPrimary)
                                .padding()
                                .background { Color.yellow }
                            Spacer()
                        }
                    }
            )
            .onAppear {
                guard animate else { return }

                withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) {
                    offset = 275
                }
            }
            .padding(2)
            .background(Color.surface)
    }
}

extension View {
    func constructionBorder(angle: Double = 45, animate: Bool = true) -> some View {
        self.modifier(ConstructionTapeBorder(angle: angle, animate: animate))
    }
}
