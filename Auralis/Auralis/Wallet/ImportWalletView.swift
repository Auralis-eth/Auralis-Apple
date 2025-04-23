//
//  ImportWalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 4/19/25.
//

import SwiftUI
import web3

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
    @State private var showBiometricOptIn: Bool = false
    @FocusState private var focusedField: Field?
    @StateObject private var biometricManager = BiometricAuthManager.shared

    @Binding public var address: String

    enum Field {
        case privateKey, password, confirmPassword
    }

    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    private var canProceed: Bool {
        isPrivateKeyValid && isPasswordValid && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Spacer()
                        Text("Import Wallet")
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
                    }

                    // Private Key Input
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Enter Private Key")
                            .fontWeight(.medium)
                            .foregroundColor(.textSecondary)

                        HStack {
                            SecureField("Private Key (64 character hex)", text: $privateKey)
                                .textContentType(.password)
                                .focused($focusedField, equals: .privateKey)
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                                .onChange(of: privateKey, initial: false) { _, _ in
                                    validatePrivateKey()
                                }
                                .foregroundColor(.textSecondary)

                            Button {
                                // Paste from clipboard functionality
                                if let clipboardString = UIPasteboard.general.string {
                                    privateKey = clipboardString
                                    validatePrivateKey()
                                }
                            } label: {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(.trailing, 8)
                            .accessibilityLabel("Paste from clipboard")
                        }

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.error)
                                .font(.caption)
                                .accessibilityLabel("Error: \(errorMessage)")
                        }

                        if isPrivateKeyValid && !derivedAddress.isEmpty {
                            Text("Derived address: \(derivedAddress)")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.top, 5)
                                .accessibilityLabel("Derived wallet address: \(derivedAddress)")
                        }
                    }
                    .padding(.horizontal)

                    // Password Input
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Create Password")
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

                    // Confirm Password
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Confirm Password")
                            .fontWeight(.medium)
                            .foregroundColor(.textSecondary)

                        HStack {
                            if password.isEmpty {
                                SecureField("Confirm password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .padding()
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                                    .foregroundColor(.textSecondary)
                                    .disabled(password.isEmpty)
                            } else {
                                SecureField("Confirm password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .padding()
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(8)
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords do not match")
                                .foregroundColor(.error)
                                .font(.caption)
                                .accessibilityLabel("Error: Passwords do not match")
                        }
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.vertical)
                        .foregroundStyle(Color.surface)

                    Text("⚠️ Handling private keys is risky. Never share your private key with anyone, and make sure you're using this app on a secure device.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("⚠️ This password is not recoverable. If you lose it, you will lose access to your wallet.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer()

                    Button {
                        showingWarningAlert = true
                    } label: {
                        Text("Import Wallet")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                canProceed
                                ? Color.accent
                                : Color.surface
                            )
                            .foregroundColor(.textSecondary)
                            .cornerRadius(10)
                    }
                    .disabled(!canProceed)
                    .padding(.horizontal)
                    .alert("Confirm Wallet Import", isPresented: $showingWarningAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Import", role: .destructive) {
                            importWallet()
                        }
                    } message: {
                        Text("You will not be able to recover your wallet without this password. Make sure you have saved it securely.")
                    }
                }
                .padding(.vertical)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showBiometricOptIn) {
                BiometricOptInView(address: $address)
            }
        }
    }

    private func validatePrivateKey() {
        // Clear previous error
        errorMessage = ""
        isPrivateKeyValid = false
        derivedAddress = ""

        // Check if private key has correct length
        let formattedKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard formattedKey.count == 64 && formattedKey.isHexIgnorePrefix, privateKey.web3.hexData != nil else {
            errorMessage = "Private key must be 64 characters long"
            return
        }

        // Check if private key is a valid hex string
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        if privateKey.unicodeScalars.contains(where: { !hexCharacterSet.contains($0) }) {
            errorMessage = "Private key must contain only hexadecimal characters (0-9, a-f, A-F)"
            return
        }

        // Try to derive the address to further validate
        do {
            guard let data = privateKey.web3.hexData else {
                return
            }

            let publicKeyData = try KeyUtil.generatePublicKey(from: data)
            let address = KeyUtil.generateAddress(from: publicKeyData)
            derivedAddress = address.asString()

            isPrivateKeyValid = true
        } catch {
            errorMessage = "Invalid private key: \(error.localizedDescription)"
        }
    }

    private func importWallet() {
        guard passwordsMatch else {
            errorMessage = "Invalid Password"
            return
        }
        do {
            let formattedKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard formattedKey.count == 64 && formattedKey.isHexIgnorePrefix, privateKey.web3.hexData != nil else {
                errorMessage = "Private key must be 64 characters long"
                return
            }

            // Check if private key is a valid hex string
            let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            if privateKey.unicodeScalars.contains(where: { !hexCharacterSet.contains($0) }) {
                errorMessage = "Private key must contain only hexadecimal characters (0-9, a-f, A-F)"
                return
            }

            let keyStorage = EthereumKeyChainStorage()

            // Create SecAccessControl for secure storage
            var error: Unmanaged<CFError>?
            let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                [.userPresence],
                &error
            )

            if let error = error {
                errorMessage = "Error setting up secure storage: \(error.takeRetainedValue().localizedDescription)"
                return
            }

            // Configure keyStorage with enhanced security
            if let accessControl = accessControl {
                keyStorage.accessControl = accessControl
            }

            // Import account using the private key
            let account = try EthereumAccount.importAccount(addingTo: keyStorage, privateKey: formattedKey, keystorePassword: password)

            let accounts = try! keyStorage.fetchAccounts()
            privateKey = ""
            print(accounts)

            // Save to keychain with enhanced security
            password.saveToKeychain()

            address = account.address.asString()

            // After successful import, show biometric opt-in if available
            if biometricManager.biometricType != .none {
                showBiometricOptIn = true
            } else {
                dismiss()
            }
        } catch {
            errorMessage = "Error importing wallet: \(error.localizedDescription)"
            print("Error importing wallet: \(error)")
        }
    }
}
