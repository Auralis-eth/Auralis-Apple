//
//  ConnectWalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import SwiftUI

struct ConnectWalletView: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            //  3)  address Entry
            VStack(spacing: 20) {
                SecondarySystemImage("wallet.pass")
                    .font(.system(size: 60))

                Title2FontText("Connect Your Wallet")

                SecondaryText("Please connect your wallet to view your NFTs")
                    .multilineTextAlignment(.center)

                Button {
                    // Connect wallet action would go here
                } label: {
                    PrimaryText("Connect Wallet")
                        .fontWeight(.medium)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(Color.secondary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical)
            .glassEffect(.regular.tint(.surface.opacity(0.2)), in: .rect(cornerRadius: 32))
        } else {
            Card3D(cardColor: .surface) {
                VStack(spacing: 20) {
                    SecondarySystemImage("wallet.pass")
                        .font(.system(size: 60))

                    Title2FontText("Connect Your Wallet")

                    SecondaryText("Please connect your wallet to view your NFTs")
                        .multilineTextAlignment(.center)

                    Button {
                        // Connect wallet action would go here
                    } label: {
                        PrimaryText("Connect Wallet")
                            .fontWeight(.medium)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.secondary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 40)
        }
    }
}
