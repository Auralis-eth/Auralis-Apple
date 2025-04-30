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

    @State private var password: Password = ""
    @State private var confirmPassword: Password = ""
    @State private var isPasswordValid: Bool = false
    @State private var showingWarningAlert: Bool = false
    @State private var errorMessage: String = ""
    @State private var useBioMetrics: Bool = true

    @FocusState private var focusedField: Field?
    @StateObject private var biometricManager = BiometricAuthManager.shared

    @Binding public var address: EOAccount?

    enum Field {
        case password, confirmPassword
    }

    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        Text("Create a New Wallet")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        Spacer()
                    }
                    .overlay {
                        HStack {
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundColor(.textSecondary)
                            }
                            .accessibilityLabel("Close")
                        }
                        .padding(.trailing)
                    }

                    VStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Enter Password")
                                .fontWeight(.medium)
                                .foregroundColor(.textSecondary)

                            PasswordField(
                                password: $password,
                                isPasswordValid: $isPasswordValid,
                                placeholder: "Password",
                                field: .password,
                                focusedField: $focusedField
                            )
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Confirm Password")
                                .fontWeight(.medium)
                                .foregroundColor(.textSecondary)

                            SecureField("Confirm password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirmPassword)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                                .foregroundColor(.textSecondary)
                                .disabled(password.isEmpty)


                            if !confirmPassword.isEmpty && !passwordsMatch {
                                Text("Passwords do not match")
                                    .foregroundColor(.error)
                                    .font(.caption)
                                    .accessibilityLabel("Error: Passwords do not match")
                            }

                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .foregroundColor(.error)
                                    .font(.caption)
                                    .accessibilityLabel("Error: \(errorMessage)")
                            }
                        }
                        .padding(.horizontal)

                        Text("⚠️ This password is not recoverable. If you lose it, you will lose access to your wallet.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    BiometricOptInView(useBioMetrics: $useBioMetrics)
                    Spacer()
                    
                    Button {
                        showingWarningAlert = true
                    } label: {
                        Text("Create Wallet")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                isPasswordValid && passwordsMatch
                                ? Color.accent
                                : Color.surface
                            )
                            .foregroundColor(.textSecondary)
                            .cornerRadius(10)
                    }
                    .disabled(!isPasswordValid || !passwordsMatch)
                    .padding(.horizontal)
                    .alert("Confirm Secure Wallet Creation", isPresented: $showingWarningAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Create", role: .destructive) {
                            createWallet()
                        }
                    } message: {
                        Text("You will not be able to recover your wallet without this password. Make sure you have saved it securely.")
                    }
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
//            modelContext.insert(eoAccount)
//            try modelContext.save()
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
