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
            WalletView(account: $mainAppStore.account, chainId: mainAppStore.chain)
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
        .tint(Color.accent)
        .constructionBorder(animate: true)
        .modelContainer(for: [NFT.self, NFT.Contract.self, NFT.Image.self, NFT.Raw.self, NFT.NFTMetadata.self, NFT.Attribute.self, NFT.Collection.self, NFT.AcquiredAt.self])
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
