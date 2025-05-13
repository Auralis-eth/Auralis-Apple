//
//  WalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import CodeScanner
import SwiftData
import SwiftUI

//import web3


// MARK: - Main WalletView
struct WalletView: View {
    @AppStorage("currentAccountAddress") var currentAddress: String = ""
    @Environment(\.modelContext) private var modelContext
    @Binding var account: EOAccount?
    @Binding var chainId: Chain
    @State private var address: String = ""
    @State private var torchOn = false
    @State private var isScanning = false
    @State private var isCreating = false
    @State private var isImporting = false

    @Query private var accounts: [EOAccount]
    var storedAccount: EOAccount? {
        guard !currentAddress.isEmpty else {
            return nil
        }

        return EOAccount(address: currentAddress)
    }
    var keychainAccounts: [EOAccount]? {
        try? EthereumKeyChainStorage().fetchAccounts().map {
            EOAccount(address: $0.asString(), access: .wallet)
        }
    }

    var allAccounts: [EOAccount] {
        var combinedAccounts = (keychainAccounts ?? []) + accounts
        if let storedAccount {
            combinedAccounts.append(storedAccount)
        }


        // Dictionary to hold unique accounts with address as the key
        var uniqueAccountsDict: [String: EOAccount] = [:]

        for account in combinedAccounts {
            let address = account.address
            if let existingAccount = uniqueAccountsDict[address] {
                // Prefer account with access: .wallet over .readonly
                if existingAccount.access == .readonly && account.access == .wallet {
                    uniqueAccountsDict[address] = account
                }
            } else {
                uniqueAccountsDict[address] = account
            }
        }

        // Return the array of unique accounts
        return Array(uniqueAccountsDict.values)
    }

    var networkSelector: some View {
        Card3D(cardColor: .surface) {
            Picker("Network", selection: $chainId) {
                ForEach(Chain.allCases) { network in
                    PrimaryText(network.networkName)
                        .tag(network)
                }
            }
            .pickerStyle(.menu)
            .tint(.secondary)
            .foregroundColor(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    networkSelector
                    Group {
                        if let storedAccount {
                            VStack {
                                SecondaryText("Your current wallet")
                                AccountListItem(account: storedAccount)

                                Button {
                                    currentAddress = ""
                                } label: {
                                    Card3D(cardColor: .surface) {
                                        HStack {
                                            SubheadlineFontText("Disconnect Wallet")
                                            AccentTextSystemImage("network.slash")
                                                .foregroundColor(.accent)  // Changed from .secondary to app's textSecondary
                                                .font(.system(size: 20, weight: .medium))
                                        }
                                    }
                                }
                            }
                        }
                        if !allAccounts.isEmpty {
                            VStack {
                                SecondaryText("Wallets")
                                ForEach(allAccounts) { storedAccount in
                                    AccountListItem(account: storedAccount)
                                        .onTapGesture {
                                            account = storedAccount
                                        }
                                }
                            }
                        }
                    }
                    .padding(.vertical)

                    WalletCell(
                        title: "Create your wallet",
                        systemImage: "wallet.pass.fill",
                        isSelected: $isCreating
                    )
                    .sheet(isPresented: $isCreating) {
                        CreateWalletView(address: $account)
                    }

                    WalletCell(
                        title: "Import your wallet",
                        systemImage: "wallet.pass",
                        isSelected: $isImporting
                    )
                    .sheet(isPresented: $isImporting) {
                        ImportWalletView(address: $account)
                    }

                    WalletCell(
                        title: "Scan your wallet",
                        systemImage: "qrcode.viewfinder",
                        isSelected: $isScanning
                    )
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

                    AddressInputView { address in
                        let eoAccount = EOAccount(address: address, access: .readonly)
                        modelContext.insert(eoAccount)
                        try? modelContext.save()
                        self.address = ""
                    }

                    deleteAllButton
                    Spacer()
                }
            }
            .padding(.horizontal)
            .background(Color.background)
        }
    }

    var deleteAllButton: some View {
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
                //delete all SwiftData accounts
                self.accounts.forEach { modelContext.delete($0) }
                try modelContext.save()
                currentAddress = ""
            } catch {
                print("Failed to delete all wallets: \(error)")
            }
        } label: {
            Card3D(cardColor: .background) {
                SubheadlineFontText("Delete ALL Wallets")
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

