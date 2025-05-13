//
//  BiometricAuthManager.swift
//  Auralis
//
//  Created by Daniel Bell on 4/19/25.
//

import LocalAuthentication
import SwiftUI

class BiometricAuthManager: ObservableObject {
    static let shared = BiometricAuthManager()

    @Published var biometricsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(biometricsEnabled, forKey: "biometricsEnabled")
        }
    }

    private let context = LAContext()
    @Published var biometricType: BiometricType = .none
    @Published var errorMessage: String = ""

    enum BiometricType {
        case none
        case faceID
        case touchID

        var description: String {
            switch self {
            case .none: return "None"
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            }
        }

        var systemImageName: String {
            switch self {
            case .none: return "xmark.circle"
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            }
        }
    }

    init() {
        self.biometricsEnabled = UserDefaults.standard.bool(forKey: "biometricsEnabled")
        checkBiometricType()
    }

    func checkBiometricType() {
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            default:
                biometricType = .none
            }
        } else {
            biometricType = .none
            if let error = error {
                errorMessage = self.getBiometricErrorMessage(from: error)
            }
        }
    }

    func authenticateWithBiometrics(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, error)
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    func getBiometricErrorMessage(from error: NSError) -> String {
        switch error.code {
        case LAError.authenticationFailed.rawValue:
            return "Authentication failed"
        case LAError.userCancel.rawValue:
            return "User canceled"
        case LAError.userFallback.rawValue:
            return "User chose to use password"
        case LAError.biometryNotAvailable.rawValue:
            return "Biometric authentication is not available"
        case LAError.biometryNotEnrolled.rawValue:
            return "No biometric data is enrolled"
        case LAError.biometryLockout.rawValue:
            return "Biometric authentication is locked out. Use your device passcode"
        case LAError.passcodeNotSet.rawValue:
            return "Device passcode is not set"
        default:
            return "Unknown error occurred"
        }
    }
}
