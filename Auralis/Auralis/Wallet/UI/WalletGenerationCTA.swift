//
//  WalletGenerationCTA.swift
//  Auralis
//
//  Created by Daniel Bell on 5/7/25.
//

import SwiftUI

struct WalletGenerationCTA: View {
    @State private var showingWarningAlert: Bool = false

    let role: Action
    var isPasswordValid: Bool

    let action: () -> Void

    var body: some View {
        Button {
            showingWarningAlert = true
        } label: {
            SecondaryText(role.buttonTitle)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    isPasswordValid
                    ? Color.accent
                    : Color.surface
                )
                .cornerRadius(10)
        }
        .disabled(!isPasswordValid)
        .padding(.horizontal)
        .alert(role.alertTitle, isPresented: $showingWarningAlert) {
            Button("Cancel", role: .cancel) { }
            Button(role.actionButtonTitle, role: .destructive, action: action)
        } message: {
            PrimaryText("You will not be able to recover your wallet without this password. Make sure you have saved it securely.")
        }
    }
}

extension WalletGenerationCTA {
    enum Action {
        case createWallet
        case importWallet

        var buttonTitle: String {
            switch self {
                case .createWallet:
                    return "Create Wallet"
                case .importWallet:
                    return "Import Wallet"
            }
        }

        var alertTitle: String {
            switch self {
                case .createWallet:
                    "Confirm Secure Wallet Creation"
                case .importWallet:
                    "Confirm Wallet Import"
            }
        }

        var actionButtonTitle: String {
            switch self {
                case .createWallet:
                    return "Create"
                case .importWallet:
                    return "Import"
            }
        }
    }
}
