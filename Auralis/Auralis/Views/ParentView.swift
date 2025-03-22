//
//  ParentView.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import SwiftUI
import SwiftData
import web3
//TODO:
//                                To-Do List:
//                                Face ID:
//                                Implement Face ID functionality
//                                Hide button if no biometric authentication is available
//                                Respect Face ID toggle
//                                Keychain Helper:
//                                Implement Keychain helper for password storage
//                                Use Face ID to save password to keychain
//                                Implement Keychain for private key storage
//                                SignInWtihApple
//                                Sign in with apple object
//TODO: create custom SwiftData EthereumAccount
struct ParentView: View {
    @Query private var keystores: [EthereumKeyStore]
    @Environment(\.modelContext) private var mc
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State private var path = NavigationPath()
    @State private var network: EthereumNetwork = .sepolia
    @State private var showChooseKeystore: Bool = false
    @State private var selectedKeystore: EthereumKeyStore?
    @State private var presentImportAlert = false
    @State private var presentPasswordAlert = false
    @State private var privateKey: String = ""

    @State private var password1: Password = ""
    @State private var password2: Password = ""

    var client: EthereumHttpClient? {
        let clientUrl = "https://sepolia.infura.io/v3/fa75668c9d754309ae8e1c8507de6d32"
        guard let url = URL(string: clientUrl) else { return nil }
        return EthereumHttpClient(url: url, network: network)
    }

    var columns: [GridItem]? {
        guard let verticalSizeClass else {
            return nil
        }

        guard let horizontalSizeClass  else {
            return nil
        }

        switch horizontalSizeClass {
            case .compact:
                switch verticalSizeClass {
                    case .compact:
                        return [GridItem(.adaptive(minimum: keystores.count == 2 ? 300 : 150))]//pro good, 15 good
                    case .regular:
                        return [GridItem(.adaptive(minimum: keystores.count == 2 ? 300 : 150))]//max good, pro good, 15 good
                }
            case .regular:
                switch verticalSizeClass {
                    case .compact:
                        return [GridItem(.adaptive(minimum: keystores.count == 2 ? 300 : 175))]//max good, plus good
                    case .regular:
                        return [GridItem(.adaptive(minimum: 300))]//ipad
                }
        }

    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack {
                HStack {
                    Picker("Network", selection: $network) {
                        ForEach(EthereumNetwork.allCases) { network in
                            Text(network.name.capitalized)
                                .tag(network)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.black)
                    .padding()
                    .foregroundColor(.black)
                    .background(Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 8)
                }
                Group {
                    if keystores.isEmpty {
                        ContentUnavailableView(
                            "NO Keystores Created",
                            systemImage: "key.slash.fill"
                        )
                    } else if keystores.count == 1 {
                        if let keystore = keystores.first {
                            KeystoreDisplayView(keystore: keystore, network: $network)
                        } else {
                            ContentUnavailableView(
                                "Keystore unavailable",
                                systemImage: "text.badge.xmark"
                            )
                        }

                    } else if let columns {
                        LazyVGrid(columns: columns) {
                            ForEach(keystores) { keystore in
                                NavigationLink(value: keystore) {
                                    KeystoreDisplayView(keystore: keystore, network: $network)
                                }
                            }
//                            .onDelete { indexSet in
//                                for index in indexSet {
//                                    mc.delete(keystores[index])
//                                }
//                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if verticalSizeClass == .regular && horizontalSizeClass == .regular {
                            Button("Add Wallet", systemImage: "plus") {
                                presentPasswordAlert = true
                            }
                            Button("Import Wallet", systemImage: "square.and.arrow.down") {
                                presentImportAlert = true
                            }
                            Button("Add Keystore", systemImage: "bag.fill.badge.plus", action: addKeystore)
                        } else {
                            Menu {
                                Button("Import Wallet", systemImage: "square.and.arrow.down") {
                                    presentImportAlert = true
                                }
                                Button("Add Keystore", systemImage: "bag.fill.badge.plus", action: addKeystore)
                                Button("Add Wallet", systemImage: "plus") {
                                    presentPasswordAlert = true
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .imageScale(.large)
                            } primaryAction: {
                                presentPasswordAlert = true
                            }
                        }
                    }
                }
                Spacer()
            }
            .navigationDestination(for: EthereumKeyStore.self) { keystore in
                EthereumKeyStoreDetailView(keystore: keystore)
            }
            .sheet(isPresented: $showChooseKeystore) {
                guard let keyStorage = selectedKeystore else { return }
                guard let privateKey = KeyUtil.generatePrivateKeyData() else { return }
                do {
                    try keyStorage.encryptAndStorePrivateKey(key: privateKey, keystorePassword: "web3swift_0")
                    try mc.save()
                } catch {
                    print(error)
                }

            } content: {
                EthereumKeyStoreSelectorView(selectedKeystore: $selectedKeystore, keystores: keystores)
            }
            .alert("Enter Private Key", isPresented: $presentImportAlert, actions: {
                TextField("private key", text: $privateKey)
                    .textInputAutocapitalization(.never)
                Button("import", action: importWallet)
                    .disabled(!isPrivatKeyValid)
                Button("Cancel", role: .cancel, action: {})
            }, message: {
                Text("Please enter your Private Key.")
            })
            .sheet(isPresented: $presentPasswordAlert) {
                AccountCreationAuthenticationView(keystores: keystores, showChooseKeystore: $showChooseKeystore)
            }
        }
    }

    func addWallet() {
        if keystores.count < 2 {
            let keyStorage = keystores.first ?? EthereumKeyStore()
            mc.insert(keyStorage)

            //        path.append(keyStorage)
            guard let privateKey = KeyUtil.generatePrivateKeyData() else { return }
            do {
                try keyStorage.encryptAndStorePrivateKey(key: privateKey, keystorePassword: "web3swift_0")
            } catch {
                print(error)
            }
        } else {
            showChooseKeystore = true
        }
    }
    
    var isPrivatKeyValid: Bool {
        guard !privateKey.isEmpty else {
            return false
        }
        let formattedKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard formattedKey.count >= 64 && formattedKey.isHexIgnorePrefix, privateKey.web3.hexData != nil else {
            return false
        }
        return true
    }
    func importWallet() {
        guard isPrivatKeyValid else {
            return
        }

        let keyStorage = EthereumKeyStore()
        mc.insert(keyStorage)
        guard let data = privateKey.web3.hexData else {
            return
        }
        do {
            try keyStorage.encryptAndStorePrivateKey(key:  data, keystorePassword: "web3swift_0")
            privateKey = ""
        } catch {
            print(error)
        }
    }

    func addKeystore() {
        let keyStorage = EthereumKeyStore()
        mc.insert(keyStorage)
    }
}

//TODO: Password
//==============================================================================
//==============================================================================
//Ticket 2: Secure Wallet Creation Using iOS Keychain and Biometric Authentication
//* Description: Implement wallet creation with secure storage of private keys using iOS Keychain.
//* Tasks:
//    * Integrate iOS Keychain for secure private key storage.
//    * Ensure wallet data is encrypted and securely stored.
//    * Test security features (biometric authentication, encrypted storage).
//==============================================================================
//  sheet size
//  sheet design/style
//      * Password Strength Indicator: Display a password strength indicator.

import LocalAuthentication
struct AccountCreationAuthenticationView: View {
    public var keystores: [EthereumKeyStore]
    @Binding var showChooseKeystore: Bool
    @Environment(\.dismiss) private var dismiss

    @Environment(\.modelContext) private var mc
    @State private var password1: Password = ""
    @State private var passwordConfirmation: Password = ""
    @State private var isPasswordValid: Bool = false
    @State var isPasswordMatch: Bool = false
    @State var isPasswordStrong: Bool = false

    @State private var isUnlocked = false
    private static let sharedContext = LAContext()
    private var context: LAContext {
        return Self.sharedContext
    }
    var biometryType: LABiometryType {
        context.biometryType
    }
    var isBiometryAvailable: Bool {
        context.biometryType != .none
    }
    var biometryTypeImage: Image {
        switch biometryType {
            case .none:
                return Image(systemName: "lock")
            case .touchID:
                return Image(systemName: "touchid")
            case .faceID:
                return Image(systemName: "faceid")
            case .opticID:
                return Image(systemName: "opticid")
            @unknown default:
                return Image(systemName: "lock")
        }
    }
    var bioDeviceType: String {
        switch biometryType {
            case .none:
                return "No Touch ID or Face ID"
            case .touchID:
                return "Touch ID"
            case .faceID:
                return "Face ID"
            case .opticID:
                return "Optic ID"
            @unknown default:
                return "Unknown Touch ID or Face ID"
        }
    }
    var body: some View {
        VStack {
            VStack {
                Text("Please enter and confirm your password to secure your wallet.")
                Text("Set Wallet Password")
            }
            .padding()
            SecureField("Enter Password", text: $password1)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityLabel(Text("Enter your password"))
            SecureField("Confirm Password", text: $passwordConfirmation)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityLabel(Text("Confirm your password"))
            if !isPasswordValid {
                Text("Passwords must match and be at least 7 characters, including a number, an uppercase, and a special character.")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }


            //handle the bio success
            if isBiometryAvailable {
                Group {
                    if isUnlocked {
                        Text("bio unlocked")
                    } else {
                        HStack {
                            Text("enable " + bioDeviceType)
                            biometryTypeImage
                        }
                        .onTapGesture(perform: authenticate)
                    }
                }
            }

            HStack {
                Button("Create", action: addWalletWithPassword)
                    .disabled(!isPasswordValid && (isBiometryAvailable && !isUnlocked))
                Button("Cancel", role: .cancel){
                    dismiss()
                }
            }
        }
        .onChange(of: password1) { _ in
            validatePasswords()
        }
        .onChange(of: passwordConfirmation) { _ in
            validatePasswords()
        }
    }

    func validatePasswords() {
        isPasswordValid = password1 == passwordConfirmation && password1.isStrong
        isPasswordMatch = password1 == passwordConfirmation
        isPasswordStrong = password1.isStrong
    }

    func addWalletWithPassword() {
        guard isPasswordValid && (!isBiometryAvailable || isUnlocked) else {
            return
        }

        if keystores.count < 2 {
            let keyStorage = keystores.first ?? EthereumKeyStore()
            mc.insert(keyStorage)

            guard let privateKey = KeyUtil.generatePrivateKeyData() else { return }
            do {
                try keyStorage.encryptAndStorePrivateKey(key: privateKey, keystorePassword: password1)

                //move into store func
                // add Biometric Authentication
                storePrivateKeyInKeychain(privateKey: privateKey)

                //test
                //create a read func and ensure it is stored
                // add Biometric Authentication
                storePasswordInKeychain(password: password1)
            } catch {
                print(error)
            }
            dismiss()
        } else {
            //TODO: handle this case
            showChooseKeystore = true
//            dismiss()
        }
    }

    //TODO: Error handling
    func authenticate() {
        let context = LAContext()
        var error: NSError?

        context.localizedCancelTitle = "Enter Username/Password"
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometricsOrCompanion, error: &error) {
            let reason = "Auralis uses Face ID to securely access and protect your private key, ensuring only you can access your encrypted data."
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometricsOrCompanion, localizedReason: reason) { success, authenticationError in
                if success {
                    //authenticated
                    isUnlocked = true
                } else {
                    //there was a problem
                }

            }
        } else {
            // no biometrics
        }
    }

    func storePrivateKeyInKeychain(privateKey: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.auralis.privatekey",
            kSecValueData as String: privateKey
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error storing private key in Keychain: \(status)")
        }
    }

    func storePasswordInKeychain(password: String) {
        let passwordData = password.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.auralis.walletpassword",
            kSecValueData as String: passwordData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Error storing password in Keychain: \(status)")
        }
    }
}

typealias Password = String
// Method to check password strength
extension Password {
    var isStrong: Bool {
        let passwordLengthRequirement = count > 7
        let containsUppercase = rangeOfCharacter(from: .uppercaseLetters) != nil
        let containsLowercase = rangeOfCharacter(from: .lowercaseLetters) != nil
        let containsDigit = rangeOfCharacter(from: .decimalDigits) != nil
        let containsSpecialCharacter = rangeOfCharacter(from: .punctuationCharacters) != nil

        // You can adjust these criteria as needed for your use case
        return passwordLengthRequirement && containsUppercase && containsLowercase && containsDigit && containsSpecialCharacter
    }

    // Password strength indicator (for UI purposes)
    var strengthIndicator: String {
        let lengthScore = count >= 8 ? 1 : 0
        let hasUppercase = rangeOfCharacter(from: CharacterSet.uppercaseLetters) != nil ? 1 : 0
        let hasLowercase = rangeOfCharacter(from: CharacterSet.lowercaseLetters) != nil ? 1 : 0
        let hasDigit = rangeOfCharacter(from: CharacterSet.decimalDigits) != nil ? 1 : 0
        let hasSpecialCharacter = rangeOfCharacter(from: CharacterSet.punctuationCharacters) != nil ? 1 : 0

        let strengthScore = lengthScore + hasUppercase + hasLowercase + hasDigit + hasSpecialCharacter

        switch strengthScore {
        case 0...2:
            return "Weak"
        case 3:
            return "Medium"
        case 4...5:
            return "Strong"
        default:
            return "Very Weak"
        }
    }
}



//
//  KeychainService.swift
//  Auralis
//
//  Created by Daniel Bell on 11/13/24.
//

import Foundation
import LocalAuthentication
import Security


//TODO: apply:
//query[kSecAttrSynchronizable as String] = kCFBooleanTrue
class KeychainService {
    enum KeychainError: Error {
        case string2DataConversionError
        case itemNotFound
        case unableToSave(String)
        case generalError(Int)
    }
    private let serviceName = "com.example.app"

    func save(value: String, forKey key: String) throws -> Bool {
        guard let encodedPassword = value.data(using: .utf8) else {
            throw KeychainError.string2DataConversionError
        }
        do {
            _ = try loadData(forKey: key)
            return try update(encodedPassword, for: key)
        } catch {
            return saveData(encodedPassword, forKey: key)
        }
    }
    func saveData(_ data: Data, forKey key: String) -> Bool {
        //TODO: verify SecAccessControlCreateWithFlags
        let accessControl = SecAccessControlCreateWithFlags(nil,
                                                            kSecAttrAccessibleWhenUnlocked,
                                                            .userPresence,
                                                            nil)
        guard let accessControlObject = accessControl else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecAttrAccessControl as String: accessControlObject,
            kSecValueData as String: data
        ]

//        var status = SecItemCopyMatching(query as CFDictionary, nil)
        //        let deleteStatus = SecItemDelete(query as CFDictionary)
        //        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
        //            return false
        //        }

        let status = SecItemAdd(query as CFDictionary, nil)
        //        if status == errSecDuplicateItem {
        //            throw Error
        //        }
        return status == errSecSuccess
    }

    func loadData(forKey key: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = "Authenticate to retrieve your data."

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            //TODO: verify kSecUseAuthenticationContext
            kSecUseAuthenticationContext as String: context
            //kSecMatchLimit as String: kSecMatchLimitOne,
            //kSecReturnAttributes as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        //        guard status != errSecItemNotFound else {
        //            throw KeychainError.itemNotFound
        //        }
        //
        //        guard status == errSecSuccess else {
        //            throw KeychainError.unexpectedStatus(status)
        //        }
        //
        //        guard let password = itemCopy as? Data else {
        //            throw KeychainError.invalidItemFormat
        //        }

        guard let data = item as? Data, status == errSecSuccess else {
            if let error = SecCopyErrorMessageString(status, nil) as String? {
                throw KeychainError.unableToSave(error)
            } else {
                throw KeychainError.generalError(Int(status))
            }
        }
        return data
    }


    func update(_ data: Data, for key: String) throws -> Bool {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ] as CFDictionary

        let updatedData = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query, updatedData)

        guard status != errSecItemNotFound else {
            throw KeychainError.itemNotFound
        }
        return status == errSecSuccess
    }

    func delete(key: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: key
        ] as CFDictionary

        let status = SecItemDelete(query)
        //        guard status == errSecSuccess else {
        //            throw KeychainError.unexpectedStatus(status)
        //        }
    }
}

//// Usage example
//let keychainService = KeychainService()
//let dataToSave = "Sensitive information".data(using: .utf8)!
//
//// Save data to Keychain
//if keychainService.saveData(dataToSave, forKey: "my_secure_key") {
//    print("Data saved successfully.")
//} else {
//    print("Failed to save data.")
//}
//
//// Retrieve data using biometrics
//do {
//    let retrievedData = try keychainService.loadData(forKey: "my_secure_key")
//    if let retrievedString = String(data: retrievedData, encoding: .utf8) {
//        print("Retrieved data: \(retrievedString)")
//    }
//} catch {
//    print("Failed to retrieve data: \(error.localizedDescription)")
//}
