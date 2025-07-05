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
    @State private var isPasswordValid: Bool = false
    @State private var isPrivateKeyValid: Bool = false
    @State private var errorMessage: String = ""

    @State private var derivedAddress: String = ""
    @State private var useBioMetrics: Bool = true
    @State private var importPhase: ImportPhase? = nil
    @FocusState private var focusedField: Field?
    @StateObject private var biometricManager = BiometricAuthManager.shared
    let keyStorage = EthereumKeyChainStorage()
    @Binding public var address: EOAccount?

    enum Field {
        case privateKey
    }

    private var canProceed: Bool {
        isPrivateKeyValid && isPasswordValid
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

                        Title2FontText("Importing Your Wallet")

                        SecondaryText("We're creating a secure wallet from your private key. This process encrypts your key with your \(biometricType.description).")
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SuccessTextSystemImage("checkmark.circle.fill")
                                SecondaryText("Validating private key")
                            }

                            HStack {
                                AccentTextSystemImage("lock.fill")
                                SecondaryText("Encrypting wallet data")
                            }
                        }
                        .padding(.vertical)

                        CalloutFontText("Please don't close the app during this process.")
                            .padding(.top)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.background)

                case .setEnhancedSecurity:
                    VStack(spacing: 20) {
                        AccentTextSystemImage(biometricType.systemImageName)
                            .font(.system(size: 60))
                            .padding(.bottom, 20)

                        Title2FontText("Enable Enhanced Security")

                        SecondaryText("We're setting up biometric authentication for your wallet. This adds an additional layer of security when accessing your funds.")
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 15) {
                            HStack(alignment: .top) {
                                SuccessTextSystemImage("shield.fill")
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    PrimaryText("Why we need \(biometricType.description)")
                                        .fontWeight(.medium)

                                    CalloutFontText("Your biometrics are used to unlock your encrypted wallet data locally. This means you can access your wallet quickly without typing your password each time.")
                                }
                            }

                            HStack(alignment: .top) {
                                SuccessTextSystemImage("lock.shield")
                                    .frame(width: 24)

                                VStack(alignment: .leading) {
                                    PrimaryText("Your data stays private")
                                        .fontWeight(.medium)

                                    CalloutFontText("Your biometric data never leaves your device and isn't stored by our app. It's handled securely by your device's operating system.")
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

                            SuccessTextSystemImage("checkmark.circle.fill")
                                .font(.system(size: 60))
                        }
                        .padding(.bottom, 10)

                        Title2FontText("Wallet Successfully Imported!")

                        SecondaryText("Your wallet has been securely imported and is ready to use.")
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                SuccessTextSystemImage("checkmark.circle.fill")
                                    .frame(width: 24)

                                SecondaryText("Private key securely encrypted")
                            }

                            HStack {
                                SuccessTextSystemImage("checkmark.circle.fill")
                                    .frame(width: 24)

                                SecondaryText("Wallet address successfully verified")
                            }

                            if useBioMetrics {
                                HStack {
                                    SuccessTextSystemImage("checkmark.circle.fill")
                                        .frame(width: 24)

                                    SecondaryText("\(biometricType.description) authentication enabled")
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
                                WalletGenerationHeader(action: .importWallet)

                                // Private Key Input
                                VStack(alignment: .leading, spacing: 5) {
                                    SecondaryText("Enter Private Key")
                                        .fontWeight(.medium)

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
                                            .foregroundStyle(Color.textSecondary)

                                        Button {
                                            // Paste from clipboard functionality
                                            if let clipboardString = UIPasteboard.general.string {
                                                privateKey = clipboardString
                                                validatePrivateKey()
                                            }
                                        } label: {
                                            SecondaryTextSystemImage( "doc.on.clipboard")
                                        }
                                        .padding(.trailing, 8)
                                        .accessibilityLabel("Paste from clipboard")
                                    }

                                    if !errorMessage.isEmpty {
                                        ErrorText(errorMessage)
                                            .accessibilityLabel("Error: \(errorMessage)")
                                    }

                                    if isPrivateKeyValid && !derivedAddress.isEmpty {
                                        SuccessText("Derived address: \(derivedAddress)")
                                            .padding(.top, 5)
                                            .accessibilityLabel("Derived wallet address: \(derivedAddress)")
                                    }
                                    CalloutFontText("⚠️ Handling private keys is risky. Never share your private key with anyone, and make sure you're using this app on a secure device.")
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)


                                }
                                .padding()
                                .background(Color.background)

                                PasswordEntryView(
                                    passwordIsValid: $isPasswordValid,
                                    errorMessage: $errorMessage,
                                    password: $password
                                )
                                BiometricOptInView(useBioMetrics: $useBioMetrics)
                                Spacer()
                                WalletGenerationCTA(role: .importWallet, isPasswordValid: canProceed) {
                                    importPhase = .setEnhancedSecurity
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
            guard isPasswordValid else {
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
                        modelContext.insert(eoAccount)

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
