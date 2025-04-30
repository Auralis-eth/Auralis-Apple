//
//  BiometricOptInView.swift
//  Auralis
//
//  Created by Daniel Bell on 4/19/25.
//

import SwiftUI

struct BiometricOptInView: View {
    @StateObject private var biometricManager = BiometricAuthManager.shared
    @Binding var useBioMetrics: Bool

    var body: some View {
        HStack {
            Image(systemName: biometricManager.biometricType.systemImageName)
                .foregroundColor(.accent)  // Changed from .secondary to app's textSecondary
                .foregroundStyle(Color.accent)
                .font(.system(size: 40, weight: .medium))

            Spacer()

            Button {
                biometricManager.biometricsEnabled = useBioMetrics
                useBioMetrics.toggle()
            } label: {
                if useBioMetrics {
                    Text("Disable \(biometricManager.biometricType.description)")
                        .fontWeight(.medium)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.surface)
                        .foregroundColor(.textSecondary)
                        .cornerRadius(10)
                } else {
                    Text("Enable \(biometricManager.biometricType.description)")
                        .fontWeight(.semibold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accent)
                        .foregroundColor(.textSecondary)
                        .cornerRadius(10)
                }
            }
        }
        .background(Color.background)
        .padding(.horizontal)
        .onAppear {
            biometricManager.biometricsEnabled = useBioMetrics
        }
    }
}
