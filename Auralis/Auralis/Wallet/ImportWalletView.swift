//
//  ImportWalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 4/19/25.
//

import SwiftUI
import web3

struct ImportWalletView: View {
    enum ImportPhase {
        case importAndSecureAccount
        case setEnhancedSecurity
        case complete
    }
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var privateKey: String = ""
    @State private var password: Password = ""
    @State private var confirmPassword: Password = ""
    @State private var isPasswordValid: Bool = false
    @State private var isPrivateKeyValid: Bool = false
    @State private var errorMessage: String = ""
    @State private var showingWarningAlert: Bool = false
    @State private var derivedAddress: String = ""
    @State private var useBioMetrics: Bool = true
    @State private var importPhase: ImportPhase? = nil
    @FocusState private var focusedField: Field?
    @StateObject private var biometricManager = BiometricAuthManager.shared
    let keyStorage = EthereumKeyChainStorage()
    @Binding public var address: EOAccount?

    enum Field {
        case privateKey, password, confirmPassword
    }

    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    private var canProceed: Bool {
        isPrivateKeyValid && isPasswordValid && passwordsMatch
    }

    private var biometricType: BiometricAuthManager.BiometricType {
        biometricManager.biometricType
    }

    var body: some View {
        Group {
            switch importPhase {
                case .importAndSecureAccount:
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 30)

                        Text("Importing Your Wallet")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)

                        Text("We're creating a secure wallet from your private key. This process encrypts your key with your \(biometricType.description).")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Validating private key")
                                    .foregroundColor(.textSecondary)
                            }

                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.accent)
                                Text("Encrypting wallet data")
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        .padding(.vertical)

                        Text("Please don't close the app during this process.")
                            .font(.callout)
                            .foregroundColor(.textSecondary)
                            .padding(.top)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.background)

                case .setEnhancedSecurity:
                    VStack(spacing: 20) {
                        Image(systemName: biometricType.systemImageName)
                            .font(.system(size: 60))
                            .foregroundColor(.accent)
                            .padding(.bottom, 20)

                        Text("Enable Enhanced Security")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)

                        Text("We're setting up biometric authentication for your wallet. This adds an additional layer of security when accessing your funds.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 15) {
                            HStack(alignment: .top) {
                                Image(systemName: "shield.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text("Why we need \(biometricType.description)")
                                        .fontWeight(.medium)
                                        .foregroundColor(.textPrimary)

                                    Text("Your biometrics are used to unlock your encrypted wallet data locally. This means you can access your wallet quickly without typing your password each time.")
                                        .foregroundColor(.textSecondary)
                                        .font(.callout)
                                }
                            }

                            HStack(alignment: .top) {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(.green)
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    Text("Your data stays private")
                                        .fontWeight(.medium)
                                        .foregroundColor(.textPrimary)

                                    Text("Your biometric data never leaves your device and isn't stored by our app. It's handled securely by your device's operating system.")
                                        .foregroundColor(.textSecondary)
                                        .font(.callout)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.background)

                case .complete:
                    VStack(spacing: 25) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 100, height: 100)

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                        }
                        .padding(.bottom, 10)

                        Text("Wallet Successfully Imported!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)

                        Text("Your wallet has been securely imported and is ready to use.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 24)

                                Text("Private key securely encrypted")
                                    .foregroundColor(.textSecondary)
                            }

                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 24)

                                Text("Wallet address successfully verified")
                                    .foregroundColor(.textSecondary)
                            }

                            if useBioMetrics {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .frame(width: 24)

                                    Text("\(biometricType.description) authentication enabled")
                                        .foregroundColor(.textSecondary)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.background)

                case nil:
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
                                .background(Color.background)
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
                                    Text("⚠️ Handling private keys is risky. Never share your private key with anyone, and make sure you're using this app on a secure device.")
                                        .foregroundColor(.secondary)
                                        .font(.callout)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)


                                }
                                .padding()
                                .background(Color.background)

                                VStack {
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
                                    .padding()

                                    // Confirm Password
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
                                    }
                                    .padding()

                                    Text("⚠️ This password is not recoverable. If you lose it, you will lose access to your wallet.")
                                        .foregroundColor(.secondary)
                                        .font(.callout)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                .background(Color.background)
                                BiometricOptInView(useBioMetrics: $useBioMetrics)
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
                                        importPhase = .setEnhancedSecurity
                                    }
                                } message: {
                                    Text("You will not be able to recover your wallet without this password. Make sure you have saved it securely.")
                                }
                            }
                            .padding(.vertical)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.background)
                        .navigationBarTitleDisplayMode(.inline)
                    }
            }
        }
        .onChange(of: importPhase, initial: false) { oldValue, newValue in
            guard passwordsMatch else {
                errorMessage = "Invalid Password"
                return
            }
            do {
                switch newValue {
                    case .setEnhancedSecurity:
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

                        // Create SecAccessControl for secure storage

                        var error: Unmanaged<CFError>?
                        let accessControl = SecAccessControlCreateWithFlags(
                            nil,
                            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                            [useBioMetrics ? .biometryAny : .userPresence],
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

                        importPhase = .importAndSecureAccount
                    case .importAndSecureAccount:
                        // Import account using the private key
                        let formattedKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        let account = try EthereumAccount.importAccount(addingTo: keyStorage, privateKey: formattedKey, keystorePassword: password)
                        privateKey = ""

                        let eoAccount = EOAccount(address: account.address.asString(), access: .wallet)
//                        modelContext.insert(eoAccount)

                        password.saveToKeychain()
                        address = eoAccount
                        importPhase = .complete
                    case .complete:
                        dismiss()
                    case .none:
                        //NO-OP
                        print("")
                }
            } catch {
                errorMessage = "Error importing wallet: \(error.localizedDescription)"
                print("Error importing wallet: \(error)")
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
}
