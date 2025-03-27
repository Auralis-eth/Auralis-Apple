//
//  MainView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/23/25.
//

import SwiftUI

struct MainView: View {
    @State private var mainAppStore = MainStore()
    var body: some View {
        TabView {
            WalletView(metamaskSDK: mainAppStore.metamaskSDK, account: $mainAppStore.account)
                .onAppear {
                    mainAppStore.account = "0x5b93ff82faaf241c15997ea3975419dddd8362c5"
                }
                .tabItem {
                    Image(systemName: "wallet.bifold.fill")
                    Text("Wallet")
                }

            NFTBrowserView(mainAppStore: $mainAppStore)
                .tabItem {
                    Image(systemName: "location.north.circle")
                    Text("NFT Browser")
                }

            GasPriceEstimateView(chainId: $mainAppStore.chainId)
                .tabItem {
                    Image(systemName: "fuelpump")
                    Text("Gas")
                }

            MusicApp(musicNFTs: mainAppStore.musicNFTs)
                .tabItem {
                    Image(systemName: "music.quarternote.3")
                    Text("Music")
                }
        }
    }
}
