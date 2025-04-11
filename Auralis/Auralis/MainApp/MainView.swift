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
            WalletView(account: $mainAppStore.account)
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

//            MusicApp(musicNFTs: mainAppStore.musicNFTs)
//                .tabItem {
//                    Image(systemName: "music.quarternote.3")
//                    Text("Music")
//                }
        }
        .tint(Color.accent)
        .modelContainer(for: [NFT.self, NFT.Contract.self, NFT.Image.self, NFT.Raw.self, NFT.NFTMetadata.self, NFT.Attribute.self, NFT.Collection.self, NFT.AcquiredAt.self])
    }
}
