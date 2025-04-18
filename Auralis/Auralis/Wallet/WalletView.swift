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
                        }
                    }

                    // Private Key Input
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Enter Private Key")
                            .fontWeight(.medium)
                            .foregroundColor(.textSecondary)

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

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.error)
                                .font(.caption)
                        }

                        if isPrivateKeyValid && !derivedAddress.isEmpty {
                            Text("Derived address: \(derivedAddress)")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.top, 5)
                        }
                    }
                    .padding(.horizontal)

                    // Password Input
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Create Password")
                            .fontWeight(.medium)
                            .foregroundColor(.textSecondary)

                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .password)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                            .onChange(of: password, initial: false) { _, _ in
                                isPasswordValid = password.strength != .weak
                            }
                            .foregroundColor(.textSecondary)

                        // Password strength indicator
                        HStack {
                            Text("Strength:")
                                .foregroundColor(.textSecondary)
                            PasswordStrengthView(strength: password.strength)
                        }
                        .padding(.top, 5)

                        Text(password.strength.message)
                            .lineLimit(nil)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.horizontal)

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

                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords do not match")
                                .foregroundColor(.error)
                                .font(.caption)
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
            //        mc.insert(keyStorage)

            // Import account using the private key
            let account = try EthereumAccount.importAccount(addingTo: keyStorage, privateKey: formattedKey, keystorePassword: password)

            let accounts = try! keyStorage.fetchAccounts()
            privateKey = ""
            print(accounts)

            // Save to keychain
            password.saveToKeychain()

            address = account.address.asString()
            dismiss()
        } catch {
            errorMessage = "Error importing wallet: \(error.localizedDescription)"
            print("Error importing wallet: \(error)")
        }
    }
}



import web3
import SwiftUI
import Security
import LocalAuthentication

struct CreateWalletView: View {
    @Environment(\.dismiss) var dismiss
    @State private var password: Password = ""
    @State private var confirmPassword: Password = ""
    @State private var isPasswordValid: Bool = false
    @State private var showingWarningAlert: Bool = false
    @FocusState private var focusedField: Field?

    @Binding public var address: String

    enum Field {
        case password, confirmPassword
    }

    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
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

                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Enter Password")
                        .fontWeight(.medium)
                        .foregroundColor(.textSecondary)

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .password)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .onChange(of: password, initial: false) { _,_  in
                            isPasswordValid = password.strength != .weak
                        }
                        .foregroundColor(.textSecondary)

                    // Password strength indicator
                    HStack {
                        Text("Strength:")
                            .foregroundColor(.textSecondary)
                        PasswordStrengthView(strength: password.strength)
                    }
                    .padding(.top, 5)

                    Text(password.strength.message)
                        .lineLimit(nil)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
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

                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords do not match")
                            .foregroundColor(.error)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.vertical)
                    .foregroundStyle(Color.surface)

                Text("⚠️ This password is not recoverable. If you lose it, you will lose access to your wallet.")
                    .foregroundColor(.secondary)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

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
                .alert("Confirm Wallet Creation", isPresented: $showingWarningAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Create", role: .destructive) {
                        createWallet()
                    }
                } message: {
                    Text("You will not be able to recover your wallet without this password. Make sure you have saved it securely.")
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
            let account = try EthereumAccount.create(replacing: keyStorage, keystorePassword: password)

            // Save to iOS keychain
            password.saveToKeychain()

            address = account.address.asString()
            dismiss()
        } catch {
            print("Error creating wallet: \(error)")
        }
    }
}

typealias Password = String

extension Password {
    var strength: PasswordStrengthView.PasswordStrength {
        if count < 5 {
            return .weak
        }

        var score = 0

        // Check for mixed case
        if rangeOfCharacter(from: .uppercaseLetters) != nil &&
           rangeOfCharacter(from: .lowercaseLetters) != nil {
            score += 1
        }

        // Check for numbers
        if rangeOfCharacter(from: .decimalDigits) != nil {
            score += 1
        }

        // Check for special characters
        let specialCharSet = CharacterSet(charactersIn: "!@#$%^&*()_-+=<>?/[]{}|~")
        if rangeOfCharacter(from: specialCharSet) != nil {
            score += 1
        }

        // Length bonus
        if count >= 8 {
            score += 1
        }

        switch score {
        case 0...1:
            return .weak
        case 2...3:
            return .medium
        default:
            return .strong
        }
    }

    func saveToKeychain() {
        // Create a keychain query
        let passwordData = data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yourapp.wallet",
            kSecAttrAccount as String: "walletPassword",
            kSecValueData as String: passwordData
        ]

        // Add to keychain
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        // Offer to save in password manager
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Save wallet password to iCloud Keychain") { success, error in
                // This would typically trigger the iOS password save dialog
            }
        }
    }
}
