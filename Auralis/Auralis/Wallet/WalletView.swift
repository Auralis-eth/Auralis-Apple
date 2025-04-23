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
    @State private var isCreating = false
    @State private var isImporting = false

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
            ScrollView {
                VStack(spacing: 16) {
                    ConnectionStatusView(account: displayAddress, connected: !account.isEmpty, chainId: "0x1")
                    Button {
                        isCreating = true
                    } label: {
                        Card3D(cardColor: .surface) {
                            HStack {
                                Text("Create your wallet")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Image(systemName: "wallet.pass.fill")
                                    .foregroundColor(.accent)  // Changed from .secondary to app's textSecondary
                                    .foregroundStyle(Color.accent)
                                    .font(.system(size: 40, weight: .medium))
                            }
                        }
                    }
                    .sheet(isPresented: $isCreating) {
                        CreateWalletView(address: $account)
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Card3D(cardColor: .surface) {
                            HStack {
                                Text("Import your wallet")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Image(systemName: "wallet.pass")
                                    .foregroundColor(.accent)
                                    .foregroundStyle(Color.accent)
                                    .font(.system(size: 40, weight: .medium))
                            }
                        }
                    }
                    .sheet(isPresented: $isImporting) {
                        ImportWalletView(address: $account)
                    }


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

//TODO:
import web3
import SwiftUI
import Security
import LocalAuthentication

struct ImportWalletView: View {
    @Environment(\.dismiss) var dismiss
    @State private var privateKey: String = ""
    @State private var password: Password = ""
    @State private var confirmPassword: Password = ""
    @State private var isPasswordValid: Bool = false
    @State private var isPrivateKeyValid: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingWarningAlert: Bool = false
    @State private var derivedAddress: String = ""
    @FocusState private var focusedField: Field?

    @Binding public var address: String

    enum Field {
        case privateKey, password, confirmPassword
    }

    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

//SwiftLint install
//========================================================================
//========================================================================
//      create an enum of read only accounts vs self
//          self accounts cannot edit the address
//expand to support multiple accounts/keys
//@Query the accounts
enum EthereumAddressAccess {
    case wallet
    case readonly

    /// Whether this address can sign transactions
    var canSign: Bool {
        switch self {
            case .wallet:
                return true
            case .readonly:
                return false
        }
    }
}
//========================================================================
//========================================================================
//    func createClient() async throws {
//        guard let clientUrl = URL(string: "https://an-infura-or-similar-url.com/123") else { return }
//        let client = EthereumHttpClient(url: clientUrl, network: .mainnet)
//
//    //    guard let clientUrl = URL(string: "wss://sepolia.infura.io/ws/v3//123") else { return }
//    //    let client = EthereumWebSocketClient(url: clientUrl, network: .mainnet)
//
//        client.eth_gasPrice { currentPrice in
//            print("The current gas price is \(currentPrice)")
//        }
//
//        let gasPrice = try await client.eth_gasPrice()
//
//    }
//}
//
//===================================================================================================================================================
//================================================================================================

//===================================================================================================================================================
//================================================================================================
