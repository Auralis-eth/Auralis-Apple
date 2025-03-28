//
//  WalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import CodeScanner
import SwiftUI
struct TorchToggleButton: View {
    @Binding var torchOn: Bool

    var body: some View {
        Button {
            torchOn.toggle()
        } label: {
            HStack {
                Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title2)
                    .foregroundColor(torchOn ? .secondary : .deepBlue) // Use yellow when on, gray when off
                Text(torchOn ? "Torch Off" : "Torch On")
                    .fontWeight(.semibold)
                    .foregroundColor(.textPrimary) // Use primary color for text
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surface) // Use system background for adaptive colors
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(ScaleButtonStyle()) // Apply custom button style for subtle animation
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}


// MARK: - Main WalletView
struct WalletView: View {
    @Binding var account: String
    @State private var torchOn = false
    @State private var isScanning = false

    private var displayAddress: String {
        if account.count > 10 {
            let start = account.prefix(6)
            let end = account.suffix(4)
            return "\(start)...\(end)"
        }
        return account
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Address bar at the top
                AddressBarView(address: $account)
                ConnectionStatusView(account: displayAddress, connected: !account.isEmpty, chainId: "0x1")
                Button {
                    isScanning = true
                } label: {
                    Card3D(cardColor: .surface) {
                        Image(systemName: "qrcode.viewfinder")
                            .foregroundColor(.accent)  // Changed from .secondary to app's textSecondary
                            .foregroundStyle(Color.accent)
                            .font(.system(size: 40, weight: .medium))
                            .padding(.leading, 4)
                    }
                }
                .sheet(isPresented: $isScanning) {
                    VStack {
                        TorchToggleButton(torchOn: $torchOn)
                        CodeScannerView(codeTypes: [.qr], requiresPhotoOutput: false, isTorchOn: torchOn) { result in
                            switch result {
                                case .success(let code):
                                    let scannedCode = code.string
                                    if scannedCode.count == 42 && scannedCode.hasPrefix("0x") {
                                        self.account = scannedCode
                                    } else if scannedCode.hasPrefix("ethereum:") {
                                        let newCode = String(scannedCode.dropFirst("ethereum:".count))
                                        if newCode.count == 42 && newCode.hasPrefix("0x") {
                                            self.account = newCode
                                        } else if newCode.hasPrefix("0x") {
                                            if let ethereumAddress = extractEthereumAddress(newCode) {
                                                self.account = ethereumAddress
                                            } else {
                                                print("")
                                            }
                                        } else {
                                            print("")
                                        }
                                    }


                                    isScanning = false
                                case .failure(let error):
                                    //                               self.scannedCode = error.localizedDescription
                                    print(error)
                            }
                        }
                    }
                }
                .presentationDetents([.fraction(0.5), .fraction(0.25), .medium, .fraction(0.75)])
                Spacer()
            }
            .padding(.horizontal)
            .background(Color.background)
        }
    }

    func extractEthereumAddress(_ input: String) -> String? {
        // Use regular expression to match Ethereum address pattern
        let addressPattern = #"(0x[a-fA-F0-9]{40})"#

        if let match = input.range(of: addressPattern, options: .regularExpression) {
            return String(input[match])
        }

        return nil
    }
}

// MARK: - Connection Status View
struct ConnectionStatusView: View {
    let account: String
    let connected: Bool
    let chainId: String

    var body: some View {
        VStack(spacing: 12) {
            if connected || !account.isEmpty{
                HStack {
                    if !account.isEmpty {
                        Text("Connected as \(account)...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
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
                }
                HStack {
                    Label {
                        Text("Connected to \(chainId.networkName)")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    } icon: {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 8, height: 8)
                    }

                    Spacer()

                    Text(chainId.formattedChainId)
                        .font(.caption)
                        .padding(6)
                        .background(Color.surface)
                        .cornerRadius(6)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 4)
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
}
