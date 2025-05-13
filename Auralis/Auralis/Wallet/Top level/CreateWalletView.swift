//
//  CreateWalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 4/19/25.
//

import SwiftUI
import web3

struct CreateWalletView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext


    @State private var useBioMetrics: Bool = true
    @State private var isPasswordValid: Bool = false
    @State private var errorMessage: String = ""
    @State private var password: Password = ""

    @Binding public var address: EOAccount?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WalletGenerationHeader(action: .createWallet)
                    PasswordEntryView(
                        passwordIsValid: $isPasswordValid,
                        errorMessage: $errorMessage,
                        password: $password
                    )

                    BiometricOptInView(useBioMetrics: $useBioMetrics)
                    Spacer()
                    WalletGenerationCTA(role: .createWallet, isPasswordValid: isPasswordValid, action: createWallet)
                }
            }
            .padding(.vertical)
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func createWallet() {
        do {
            let keyStorage = EthereumKeyChainStorage()

            // Create SecAccessControl for secure storage
            var error: Unmanaged<CFError>?
            let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [ useBioMetrics ? .biometryAny : .userPresence],
                &error
            )

            if let error = error {
                errorMessage = "Error setting up secure storage: \(error.takeRetainedValue().localizedDescription)"
                return
            }

            // Configure keyStorage with enhanced security
            //FACEID USED
            if let accessControl = accessControl {
                keyStorage.accessControl = accessControl
            }
            //FACEID USED
            let account = try EthereumAccount.create(addingTo: keyStorage, keystorePassword: password)

            let eoAccount = EOAccount(address: account.address.asString(), access: .wallet)
            modelContext.insert(eoAccount)
            try modelContext.save()
            // Save to iOS keychain with enhanced security
            password.saveToKeychain()

            address = eoAccount

            // After successful wallet creation, show biometric opt-in if available
            dismiss()
        } catch {
            errorMessage = "Error creating wallet: \(error.localizedDescription)"
            print("Error creating wallet: \(error)")
        }
    }
}
