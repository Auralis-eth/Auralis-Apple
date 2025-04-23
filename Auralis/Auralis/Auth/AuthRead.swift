//
//  AuthRead.swift
//  Auralis
//
//  Created by Daniel Bell on 4/21/25.
//

//import web3
//import SwiftUI
//import Security
//import LocalAuthentication
//// MARK: - Authentication Helper
//
//struct AuthHelper {
//    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
//        let biometricManager = BiometricAuthManager.shared
//
//        if biometricManager.biometricsEnabled {
//            // Try biometric authentication first
//            biometricManager.authenticateWithBiometrics(reason: reason) { success, error in
//                if success {
//                    completion(true)
//                } else {
//                    // Fall back to password
//                    authenticateWithPassword(completion: completion)
//                }
//            }
//        } else {
//            // Go directly to password authentication
//            authenticateWithPassword(completion: completion)
//        }
//    }
//
//    static func authenticateWithPassword(completion: @escaping (Bool) -> Void) {
//        // In real implementation, show a password prompt and validate against stored password
//        if let storedPassword = Password.loadFromKeychain() {
//            // Show password entry dialog
//            // Compare entered password with storedPassword
//            // For demonstration purposes, we're auto-succeeding
//            completion(true)
//        } else {
//            completion(false)
//        }
//    }
//}
//
//// MARK: - Example Usage for Authentication
//
//class WalletManager {
//    func signTransaction(for address: String, completion: @escaping (Bool) -> Void) {
//        // First authenticate the user
//        AuthHelper.authenticate(reason: "Sign transaction from your wallet") { success in
//            if success {
//                // Proceed with transaction signing
//                // Access the keychain item which will be protected with the security controls
//                print("Authentication successful, proceeding with signing")
//                completion(true)
//            } else {
//                print("Authentication failed")
//                completion(false)
//            }
//        }
//    }
//}
