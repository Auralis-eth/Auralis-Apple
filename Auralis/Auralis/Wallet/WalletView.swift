//
//  WalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import CodeScanner
import SwiftData
import SwiftUI

extension String {
    var displayAddress: String {
        if count > 10 {
            let start = prefix(6)
            let end = suffix(4)
            return "\(start)...\(end)"
        }
        return self
    }
}

// MARK: - Main WalletView
struct WalletView: View {
    @Environment(\.modelContext) private var modelContext

    @Binding var account: EOAccount?
    @Binding var chainId: Chain
    @State private var address: String = ""
    @State private var torchOn = false
    @State private var isScanning = false
    @State private var isCreating = false
    @State private var isImporting = false

    @Query private var accounts: [EOAccount]

    var networkSelector: some View {
        Card3D(cardColor: .surface) {
            Picker("Network", selection: $chainId) {
                ForEach(Chain.allCases) { network in
                    Text(network.networkName)
                        .tag(network)
                }
            }
            .pickerStyle(.menu)
            .tint(.secondary)
            .foregroundColor(.secondary)
        }
    }


    //TODO: Wallet View

    // 3) create account changer

    //accounts has 0 objects
    //accounts has 1 object
    //accounts has multiple objects

    //more than 0
    //  create objects go in a new view behind a button
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    //TODO: pass in account object itself
                    //TODO: add in elipses menu with a delete action
                    //TODO: add readonly vs wallet indicator
                    networkSelector
//                    List {
                        ForEach(accounts) { storedAccount in
                            ConnectionStatusView(
                                account: storedAccount.address.displayAddress,
                                connected: !storedAccount.address.isEmpty
                            )
                        }
//                        .onDelete(perform: delete)
//                    }
//                    .onAppear {
//                        processAccount()
//                    }

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
                                            let eoAccount = EOAccount(address: scannedCode, access: .readonly)
                                            modelContext.insert(eoAccount)
//                                            self.account = eoAccount
                                        } else if scannedCode.hasPrefix("ethereum:") {
                                            let newCode = String(scannedCode.dropFirst("ethereum:".count))
                                            if newCode.count == 42 && newCode.hasPrefix("0x") {
                                                let eoAccount = EOAccount(address: newCode, access: .readonly)
                                                modelContext.insert(eoAccount)
//                                                self.account = eoAccount
                                            } else if newCode.hasPrefix("0x") {
                                                if let ethereumAddress = extractEthereumAddress(newCode) {
                                                    let eoAccount = EOAccount(address: ethereumAddress, access: .readonly)
                                                    modelContext.insert(eoAccount)
//                                                    self.account = eoAccount
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
                        }
                    }
                    .presentationDetents([.fraction(0.5), .fraction(0.25), .medium, .fraction(0.75)])
                    Card3D(cardColor: .surface) {
                        VStack {
                            Text("Paste Your Address Here")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                            TextEditor(text: $address)
                                .onSubmit {
                                    let eoAccount = EOAccount(address: address, access: .readonly)
                                    modelContext.insert(eoAccount)
                                    try? modelContext.save()
                                    address = ""
                                }
                                .font(.body)  // Use your desired font
                                .fixedSize(horizontal: false, vertical: true)
                                .scrollContentBackground(.hidden)
                                .foregroundColor(.textPrimary)
                                .background(Color.surface)
                        }
                    }
                    Button {
                        do {
                            let keyStorage = EthereumKeyChainStorage()
                            try keyStorage.deleteAllKeys()
                            let accounts = try keyStorage.fetchAccounts()
                            for address in accounts {
                                do {
                                    try keyStorage.deletePrivateKey(for: address)
                                } catch {
                                    print("Failed to Delete address \(address.asString()): \(error)")
                                }
                            }
                        } catch {
                            print("Failed to delete all wallets: \(error)")
                        }
                    } label: {
                        Card3D(cardColor: .background) {
                            Text("Delete ALL Wallets")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
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

    func processAccount() {
        guard !accounts.isEmpty else {
            return
        }

        guard var keychainAccounts = try? EthereumKeyChainStorage().fetchAccounts(), !keychainAccounts.isEmpty else {
            return
        }

        // Filter out accounts with matching addresses
        keychainAccounts = keychainAccounts.filter { keyChainAccount in
            !accounts.contains { $0.address == keyChainAccount.asString() }
        }

        keychainAccounts.forEach { ethAddress in
            modelContext.insert(EOAccount(address: ethAddress.asString(), access: .wallet))
        }
        try? modelContext.save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(accounts[index])
        }
    }
}


import CodeScanner
import SwiftUI
import web3

struct MainVIewEmptyAddress: View {
    @Binding var account: EOAccount?
    @Query private var accounts: [EOAccount]

    @State private var isCreating = false
    @State private var isImporting = false
    @State private var isScanning = false
    @State private var torchOn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Accounts")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                        .padding(.top)

                    // Account List Section
                    if !accounts.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your Accounts")
                                    .font(.headline)
                                    .foregroundColor(.textSecondary)
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

                        Divider()
                            .padding(.vertical)
                            .foregroundStyle(Color.surface)
                    }

                    // Create Options Section
                    VStack(spacing: 16) {
                        Text(accounts.isEmpty ? "Get Started" : "Add New Account")
                            .font(.headline)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal)

                        ScrollView {
                            // Create Wallet Option
                            Button {
                                isCreating = true
                            } label: {
                                Card3D(cardColor: .surface) {
                                    HStack {
                                        Text("Create a new wallet")
                                            .font(.subheadline)
                                            .foregroundColor(.textSecondary)
                                        Spacer()
                                        Image(systemName: "wallet.pass.fill")
                                            .foregroundColor(.accent)
                                            .foregroundStyle(Color.accent)
                                            .font(.system(size: 40, weight: .medium))
                                    }
                                }
                            }
                            .sheet(isPresented: $isCreating) {
                                CreateWalletView(address: $account)
                            }

                            // Import Wallet Option
                            Button {
                                isImporting = true
                            } label: {
                                Card3D(cardColor: .surface) {
                                    HStack {
                                        Text("Import an existing wallet")
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

                            // Scan Wallet Option
                            Button {
                                isScanning = true
                            } label: {
                                Card3D(cardColor: .surface) {
                                    HStack {
                                        Text("Scan wallet QR code")
                                            .font(.subheadline)
                                            .foregroundColor(.textSecondary)
                                        Spacer()
                                        Image(systemName: "qrcode.viewfinder")
                                            .foregroundColor(.accent)
                                            .foregroundStyle(Color.accent)
                                            .font(.system(size: 40, weight: .medium))
                                    }
                                }
                            }
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
                        Card3D(cardColor: .surface) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Add a read-only address")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)

                                ReadOnlyAddressInput { address in
                                    account = EOAccount(address: address, access: .readonly)
                                }
                            }
                            .padding(.vertical, 4)
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

// Supporting Views
struct AccountListItem: View {
    let account: EOAccount

    var body: some View {
        Card3D(cardColor: .surface) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name ?? "Account")
                    .font(.headline)
                    .foregroundColor(.textPrimary)

                Text(account.address.displayAddress)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)

                HStack {
                    if account.access == .wallet {
                        Label("Wallet", systemImage: "key.fill")
                            .foregroundColor(.accent)
                    } else {
                        Label("Read-only", systemImage: "eye")
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal)
    }
}

struct ReadOnlyAddressInput: View {
    @State private var address: String = ""
    @State private var isAddressValid: Bool = false
    var onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("Enter Ethereum address (0x...)", text: $address)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .onChange(of: address) { _, newValue in
                    validateAddress(newValue)
                }

            Button {
                onSubmit(address)
            } label: {
                Text("Add Address")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isAddressValid ? Color.accent : Color.surface)
                    .foregroundColor(.textSecondary)
                    .cornerRadius(10)
            }
            .disabled(!isAddressValid)
        }
    }

    private func validateAddress(_ address: String) {
        // Simple validation - should be 42 chars with 0x prefix
        isAddressValid = address.count == 42 && address.hasPrefix("0x")
    }
}
