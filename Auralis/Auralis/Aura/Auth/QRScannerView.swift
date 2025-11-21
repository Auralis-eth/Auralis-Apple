//
//  QRScannerView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import CodeScanner
import SwiftUI

struct QRScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isScanning = false
    @State private var torchOn = false
    @Binding var account: EOAccount?

    var body: some View {
        Button {
            isScanning = true
        } label: {
            SystemImage("qrcode.viewfinder")
                .foregroundStyle(Color.accent)
                .font(.system(size: 30, weight: .medium))
                .accessibilityLabel("Scan wallet QR code")
        }
        .sheet(isPresented: $isScanning) {
            ZStack(alignment: .top) {
                CodeScannerView(codeTypes: [.qr], requiresPhotoOutput: false, isTorchOn: torchOn) { result in
                    switch result {
                        case .success(let code):
                            let scannedCode = code.string
                            if scannedCode.count == 42 && scannedCode.hasPrefix("0x") {
                                let eoAccount = EOAccount(address: scannedCode, access: .readonly)
                                modelContext.insert(eoAccount)
                                self.account = eoAccount
                            } else if scannedCode.hasPrefix("ethereum:") {
                                let newCode = String(scannedCode.dropFirst("ethereum:".count))
                                if newCode.count == 42 && newCode.hasPrefix("0x") {
                                    let eoAccount = EOAccount(address: newCode, access: .readonly)
                                    modelContext.insert(eoAccount)
                                    self.account = eoAccount
                                } else if newCode.hasPrefix("0x") {
                                    if let ethereumAddress = extractEthereumAddress(newCode) {
                                        let eoAccount = EOAccount(address: ethereumAddress, access: .readonly)
                                        modelContext.insert(eoAccount)
                                        self.account = eoAccount
                                    } else {
                                        print("")
                                    }
                                } else {
                                    print("")
                                }
                                try? modelContext.save()
                            }
                        case .failure(let error):
                            //                               self.scannedCode = error.localizedDescription
                            print(error)
                    }
                    isScanning = false

                }
                .ignoresSafeArea()

                TorchToggleButton(torchOn: $torchOn)
                    .padding(.top)
            }
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
