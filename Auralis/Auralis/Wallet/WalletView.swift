//
//  WalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import CodeScanner
import SwiftUI

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
                        HStack {
                            Text("Scan your wallet")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundColor(.accent)  // Changed from .secondary to app's textSecondary
                                .foregroundStyle(Color.accent)
                                .font(.system(size: 40, weight: .medium))
                                .padding(.leading, 4)
                        }
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
                Card3D(cardColor: .surface) {
                    VStack {
                        Text("Paste Your Address Here")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        TextEditor(text: $account)
                            .font(.body)  // Use your desired font
                            .fixedSize(horizontal: false, vertical: true)
                            .scrollContentBackground(.hidden)
                            .foregroundColor(.textPrimary)
                            .background(Color.surface)
                    }
                }
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
