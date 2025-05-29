//
//  AccountListItem.swift
//  Auralis
//
//  Created by Daniel Bell on 4/30/25.
//

import SwiftUI
import web3

struct AccountListItem: View {
    @Environment(\.modelContext) private var modelContext
    let account: EOAccount
    private var address: String {
        account.address.displayAddress
    }
    private var connected: Bool {
        !account.address.isEmpty
    }

    var body: some View {
        Card3D(cardColor: .surface) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let name = account.name {
                        HeadlineFontText(name)
                        SubheadlineFontText(account.address.displayAddress)
                    } else {
                        SubheadlineFontText("Connected as \(address)...")
                    }

                    Spacer()

                    Menu {
                        Button(action: {
                            modelContext.delete(account)
                            try? EthereumKeyChainStorage().deletePrivateKey(for: EthereumAddress(account.address))
                        }) {
                            Label("Delete", systemImage: "delete.left.fill")
                        }

                        Button(action: {
//                            try? EthereumKeyChainStorage().deletePrivateKey(for: EthereumAddress(account.address))
                            let privateKey = try? EthereumKeyChainStorage().loadPrivateKey(for: EthereumAddress(account.address))
                            if let privateKey, !privateKey.isEmpty {
                                account.access = .wallet
                            } else {
                                account.access = .readonly
                            }
                        }) {
                            Label("Sync", systemImage: "gearshape.arrow.triangle.2.circlepath")
                        }
                    } label: {
                        SystemImage("ellipsis")
                            .padding(8)
                    }
                }

                HStack {
                    if account.access == .wallet {
                        Label("Wallet", systemImage: "key.fill")
                            .foregroundColor(.accent)
                    } else if account.access == .readonly {
                        Label("Read-only", systemImage: "eye")
                            .foregroundColor(.textSecondary)
                    } else {
                        Label("Unknown", systemImage: "questionmark")
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()
                    if connected {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 8, height: 8)
                    }
                }
                .font(.caption)
                .background(Color.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.deepBlue.opacity(0.2), lineWidth: 1)
                )
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal)
    }
}
