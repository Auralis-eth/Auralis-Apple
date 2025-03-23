//
//  WalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import SwiftUI
import metamask_ios_sdk

// MARK: - Main WalletView
struct WalletView: View {
    @ObservedObject var metamaskSDK: MetaMaskSDK
    @Binding var account: String

    var body: some View {
        VStack(spacing: 16) {
            // Address bar at the top
            AddressBarView(address: $account) {
                await refreshWalletData()
            }

            // Connection status section
            connectionStatusView

            Spacer()
        }
        .padding(.horizontal)
        .background(Color.background)
        .onChange(of: metamaskSDK.account) { _, _ in
            account = metamaskSDK.account
        }
        .onAppear {
            account = metamaskSDK.account
        }
    }

    // MARK: - Connection Status View
    private var connectionStatusView: some View {
        VStack(spacing: 12) {
            if metamaskSDK.connected {
                HStack {
                    Label {
                        Text("Connected to \(networkName)")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    } icon: {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 8, height: 8)
                    }

                    Spacer()

                    Text(formattedChainId)
                        .font(.caption)
                        .padding(6)
                        .background(Color.surface)
                        .cornerRadius(6)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 4)

                WalletButtonView(metamaskSDK: metamaskSDK, action: .disconnect)
            } else {
                HStack {
                    Label {
                        Text("Not connected to any wallet")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    } icon: {
                        Circle()
                            .fill(Color.error)
                            .frame(width: 8, height: 8)
                    }

                    Spacer()
                }
                .padding(.horizontal, 4)

                WalletButtonView(metamaskSDK: metamaskSDK, action: .connect)
            }
        }
        .padding()
        .background(Color.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.deepBlue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Helper Functions & Computed Properties
    private var networkName: String {
        switch metamaskSDK.chainId {
        case "0x1":
            return "Ethereum Mainnet"
        case "0x89":
            return "Polygon"
        case "0xaa36a7":
            return "Sepolia Testnet"
        default:
            return "Chain ID: \(metamaskSDK.chainId)"
        }
    }

    private var formattedChainId: String {
        return "Chain ID: \(metamaskSDK.chainId)"
    }

    private func refreshWalletData() async {
        // Placeholder for wallet data refresh logic
        // Would implement actual refresh logic here
    }
}

// MARK: - WalletButtonView
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
                Image(systemName: action == .disconnect ? "link.badge.minus" : "link.badge.plus")
                    .font(.system(size: 18))

                Text(action == .disconnect ? "Disconnect MetaMask" : "Connect MetaMask")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(action == .disconnect ? Color.error.opacity(0.8) : Color.secondary)
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.2), radius: 3)
        }
    }
}
