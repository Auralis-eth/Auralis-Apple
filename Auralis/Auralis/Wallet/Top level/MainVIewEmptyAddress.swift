//
//  MainVIewEmptyAddress.swift
//  Auralis
//
//  Created by Daniel Bell on 4/30/25.
//

import CodeScanner
import SwiftData
import SwiftUI


struct WalletCell: View {
    let title: String
    let systemImage: String
    @Binding var isSelected: Bool
    var body: some View {
        Button {
            isSelected = true
        } label: {
            Card3D(cardColor: .surface) {
                HStack {
                    SubheadlineFontText(title)
                    Spacer()
                    AccentTextSystemImage(systemImage)
                        .foregroundStyle(Color.accent)  // Changed from .secondary to app's textSecondary
                        .font(.system(size: 40, weight: .medium))
                }
            }
        }
    }
}

struct AddressInputView: View {
    var onSubmit: (String) -> Void
    var body: some View {
        Card3D(cardColor: .surface) {
            VStack(alignment: .leading, spacing: 10) {
                SubheadlineFontText("Add a read-only address")
                //SubheadlineFontText("Paste Your Address Here")
                ReadOnlyAddressInput(onSubmit: onSubmit)
            }
            .padding(.vertical, 4)
        }
    }
}

struct MainVIewEmptyAddress: View {
    @Binding var account: EOAccount?
    @Query private var accounts: [EOAccount]

    @State private var isCreating = false
    @State private var isImporting = false
    @State private var isScanning = false
    @State private var torchOn = false

    var accountSelector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HeadlineFontText("Your Accounts")
                    .padding(.horizontal)

                ForEach(accounts) { acc in
                    Button {
                        account = acc
                    } label: {
                        AccountListItem(account: acc)
                    }
                }
            }
        }
        .frame(maxHeight: 150)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TitleFontText(text: "Accounts")
                        .padding(.top)

                    // Account List Section
                    if !accounts.isEmpty {
                        accountSelector

                        Divider()
                            .padding(.vertical)
                            .foregroundStyle(Color.surface)
                    }

                    // Create Options Section
                    VStack(spacing: 16) {
                        HeadlineFontText(accounts.isEmpty ? "Get Started" : "Add New Account")
                            .padding(.horizontal)

                        ScrollView {
                            // Create Wallet Option
                            WalletCell(
                                title: "Create a new wallet",
                                systemImage: "wallet.pass.fill",
                                isSelected: $isCreating
                            )
                            .sheet(isPresented: $isCreating) {
                                CreateWalletView(address: $account)
                            }

                            // Import Wallet Option
                            WalletCell(
                                title: "Import an existing wallet",
                                systemImage: "wallet.pass",
                                isSelected: $isImporting
                            )
                            .sheet(isPresented: $isImporting) {
                                ImportWalletView(address: $account)
                            }

                            // Scan Wallet Option
                            WalletCell(
                                title: "Scan wallet QR code",
                                systemImage: "qrcode.viewfinder",
                                isSelected: $isScanning
                            )
                            .sheet(isPresented: $isScanning) {
                                VStack {
                                    TorchToggleButton(torchOn: $torchOn)
                                    CodeScannerView(codeTypes: [.qr], requiresPhotoOutput: false, isTorchOn: torchOn) { result in
                                        handleScanResult(result)
                                    }
                                }
                                .presentationDetents([.fraction(0.5), .fraction(0.25), .medium, .fraction(0.75)])
                            }
                        }

                        // Read-only Address Option
                        AddressInputView { address in
                            account = EOAccount(address: address, access: .readonly)
                        }
                    }

                    Spacer()
                }
            }
            .padding(.horizontal)
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func handleScanResult(_ result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let code):
            let scannedCode = code.string
            processScannedAddress(scannedCode)
            isScanning = false
        case .failure(let error):
            print("Scanning error: \(error.localizedDescription)")
        }
    }

    private func processScannedAddress(_ scannedCode: String) {
        // Process directly valid Ethereum address
        if scannedCode.count == 42 && scannedCode.hasPrefix("0x") {
            createAccountFromAddress(scannedCode)
        }
        // Process Ethereum URI scheme
        else if scannedCode.hasPrefix("ethereum:") {
            let newCode = String(scannedCode.dropFirst("ethereum:".count))
            if newCode.count == 42 && newCode.hasPrefix("0x") {
                createAccountFromAddress(newCode)
            } else if newCode.hasPrefix("0x") {
                if let ethereumAddress = extractEthereumAddress(newCode) {
                    createAccountFromAddress(ethereumAddress)
                }
            }
        }
    }

    private func createAccountFromAddress(_ address: String) {
        if let existingAccount = accounts.first(where: { $0.address == address }) {
            account = existingAccount
        } else {
            account = EOAccount(address: address, access: .readonly)
        }
    }

    private func extractEthereumAddress(_ input: String) -> String? {
        let addressPattern = #"(0x[a-fA-F0-9]{40})"#
        if let match = input.range(of: addressPattern, options: .regularExpression) {
            return String(input[match])
        }
        return nil
    }
}

