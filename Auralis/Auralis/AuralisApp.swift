//
//  AuralisApp.swift
//  Auralis
//
//  Created by Daniel Bell on 10/20/24.
//

import SwiftUI
import SwiftData
import metamask_ios_sdk

@main
struct AuralisApp: App {
    let appMetadata = AppMetadata(
        name: "Auralis.ETH",
        url: "Auralis.eth",//"https://dubdapp.com",
        iconUrl: "https://pbs.twimg.com/profile_images/1846931552753930242/on5jhKP6_400x400.jpg"
    )
    @ObservedObject var metamaskSDK: MetaMaskSDK
    @State var account: String = "0x183AbE67478eB7E87c96CA28E2f63Dec53f22E3A"

    @MainActor @preconcurrency init() {
        metamaskSDK = MetaMaskSDK.shared(
            appMetadata,
            transport: .socket,
            //sdkOptions: SDKOptions(infuraAPIKey: Secrets.apiKey(.infura) ?? "", readonlyRPCMap: ["0x1": "hptts://www.testrpc.com"]) // for read-only RPC calls
            sdkOptions: SDKOptions(infuraAPIKey: Secrets.apiKey(.infura) ?? "") // for read-only RPC calls
            )
    }

    var body: some Scene {
        //                    ParentView()
        WindowGroup {
            TabView {
                //TODO: extract chain
                WalletView(metamaskSDK: metamaskSDK, account: $account)
                    .onAppear {
                        account = "0x183AbE67478eB7E87c96CA28E2f63Dec53f22E3A"
                    }
                    .tabItem {
                        Image(systemName: "wallet.bifold.fill")
                        Text("Wallet")
                    }

                //TODO: fix UI
                NFTBrowserView(address: $account)
                    .tabItem {
                        Image(systemName: "location.north.circle")
                        Text("NFT Browser")
                    }

                GasPriceEstimateView()
                    .tabItem {
                        Image(systemName: "fuelpump")
                        Text("Gas")
                    }


            }
        }
#if os(macOS)
        Settings {
            Text("Settings")
        }
        //MenuBarExtra(content: <#T##() -> _#>, label: <#T##() -> _#>)
        MenuBarExtra {
            Text("Settings")
        }.menuBarExtraStyle(.window)
#endif
    }
}


