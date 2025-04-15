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

// 1) EthereumKeyChainStorage
//      B) extract the keychain code
//              savePasswordToKeychain
//private func savePasswordToKeychain(password: String) {


// 3) clean up create code


// 3) connect keys and my account object
//      A) public class EthereumAccount: EthereumAccountProtocol
// TODO:
//      create an enum of read only accounts vs self
//          self accounts cannot edit the address
//expand to support multiple accounts/keys


//on app load try and get the private key
//look at the old code for any account stuff I want





import web3
import SwiftUI
import web3
import Security
import LocalAuthentication

struct CreateWalletView: View {
    @Environment(\.dismiss) var dismiss
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isPasswordValid: Bool = false
    @State private var showingWarningAlert: Bool = false
    @FocusState private var focusedField: Field?

    @Binding public var address: String

    enum Field {
        case password, confirmPassword
    }

    private var passwordsMatch: Bool {
        return password == confirmPassword && !password.isEmpty
    }

    private var passwordStrength: PasswordStrength {
        return getPasswordStrength(password)
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
                            isPasswordValid = passwordStrength != .weak
                        }
                        .foregroundColor(.textSecondary)

                    // Password strength indicator
                    HStack {
                        Text("Strength:")
                            .foregroundColor(.textSecondary)
                        PasswordStrengthView(strength: passwordStrength)
                    }
                    .padding(.top, 5)

                    Text(passwordStrengthMessage)
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
            savePasswordToKeychain(password: password)

            address = account.address.asString()
            dismiss()
        } catch {
            print("Error creating wallet: \(error)")
        }
    }

    private func savePasswordToKeychain(password: String) {
        // Create a keychain query
        let passwordData = password.data(using: .utf8)!
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

    private var passwordStrengthMessage: String {
        switch passwordStrength {
        case .weak:
            return "Use at least 8 characters with numbers, symbols, and mixed case letters."
        case .medium:
            return "Good password, but consider adding more complexity."
        case .strong:
            return "Strong password!"
        }
    }

    enum PasswordStrength {
        case weak, medium, strong
    }

    private func getPasswordStrength(_ password: String) -> PasswordStrength {
        if password.count < 5 {
            return .weak
        }

        var score = 0

        // Check for mixed case
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil &&
           password.rangeOfCharacter(from: .lowercaseLetters) != nil {
            score += 1
        }

        // Check for numbers
        if password.rangeOfCharacter(from: .decimalDigits) != nil {
            score += 1
        }

        // Check for special characters
        let specialCharSet = CharacterSet(charactersIn: "!@#$%^&*()_-+=<>?/[]{}|~")
        if password.rangeOfCharacter(from: specialCharSet) != nil {
            score += 1
        }

        // Length bonus
        if password.count >= 8 {
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
}

struct PasswordStrengthView: View {
    let strength: CreateWalletView.PasswordStrength

    var body: some View {
        HStack(spacing: 2) {
            Rectangle()
                .frame(height: 5)
                .foregroundColor(strengthColor(for: .weak))

            Rectangle()
                .frame(height: 5)
                .foregroundColor(strengthColor(for: .medium))

            Rectangle()
                .frame(height: 5)
                .foregroundColor(strengthColor(for: .strong))
        }
        .frame(width: 100)
    }

    private func strengthColor(for level: CreateWalletView.PasswordStrength) -> Color {
        switch (level, strength) {
        case (.weak, .weak), (.medium, .weak), (.strong, .weak):
            return .red
        case (.medium, .medium), (.strong, .medium):
            return .orange
        case (.strong, .strong):
            return .green
        default:
            return Color.gray.opacity(0.3)
        }
    }
}


// Importing required for LAContext

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
//
