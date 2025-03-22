//
//  WalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import SwiftUI
import metamask_ios_sdk

struct WalletView: View {
    @ObservedObject var metamaskSDK: MetaMaskSDK
    @Binding var account: String
    var body: some View {
        VStack {
            AddressBarView(address: $account)

            if metamaskSDK.connected {
                Text(metamaskSDK.chainId)
                WalletButtonView(metamaskSDK: metamaskSDK, action: .disconnect)
            } else {
                WalletButtonView(metamaskSDK: metamaskSDK, action: .connect)
            }
        }
        .onChange(of: metamaskSDK.account, initial: true) {//oldState, newState in
            account = metamaskSDK.account
        }
        .onAppear {
            account = metamaskSDK.account
        }
    }
}

struct WalletButtonView: View {
    enum Action {
        case connect
        case disconnect
    }
    @ObservedObject var metamaskSDK: MetaMaskSDK
    let action: Action
    var body: some View {
        Button {
            Task {
                if action == .disconnect {
                    metamaskSDK.terminateConnection()
                } else {
                    _ = await metamaskSDK.connect()
                }
            }
        } label: {
            HStack {
                Image(systemName: "link")
                    .font(.system(size: 18))

                Text(action == .disconnect ? "Disconnect MetaMask" : "conect MetaMask")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.orange)
            .cornerRadius(10)
            .shadow(radius: 3)
        }
    }
}

