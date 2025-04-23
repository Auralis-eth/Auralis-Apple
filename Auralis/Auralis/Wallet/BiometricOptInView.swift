//
//  BiometricOptInView.swift
//  Auralis
//
//  Created by Daniel Bell on 4/19/25.
//

import SwiftUI

struct BiometricOptInView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var biometricManager = BiometricAuthManager.shared
    @Binding var address: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: biometricManager.biometricType.systemImageName)
                .font(.system(size: 60))
                .foregroundColor(.accent)
                .padding(.top, 30)

            Text("Enable \(biometricManager.biometricType.description)?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)

            Text("Use \(biometricManager.biometricType.description) for faster and more secure access to your wallet.")
                .multilineTextAlignment(.center)
                .foregroundColor(.textSecondary)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 15) {
                Button {
                    biometricManager.biometricsEnabled = true
                    dismiss()
                } label: {
                    Text("Enable \(biometricManager.biometricType.description)")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accent)
                        .foregroundColor(.textSecondary)
                        .cornerRadius(10)
                }

                Button {
                    biometricManager.biometricsEnabled = false
                    dismiss()
                } label: {
                    Text("Skip")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.surface)
                        .foregroundColor(.textSecondary)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Color.background)
    }
}
