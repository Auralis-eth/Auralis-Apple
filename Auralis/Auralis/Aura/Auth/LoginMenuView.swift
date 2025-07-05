//
//  LoginMenuView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI

struct LoginMenuView: View {
    @Binding var authFlavour: LoginView.AuthFlavor
    @Binding var currentAccount: EOAccount?
    @Binding var isAddressExpanded: Bool
    @Namespace private var namespace

    var body: some View {
        // Buttons
        VStack(spacing: 16) {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10.0) {
                    if isAddressExpanded {
                        AddressEntryView(currentAccount: $currentAccount)
                            .glassEffectID("address-entry", in: namespace)
                            .glassEffectTransition(.matchedGeometry)
                            .matchedGeometryEffect(id: "glassCard", in: namespace)
                    } else {
                        Button(action: {
                            withAnimation {
                                isAddressExpanded = true
                            }
                        }) {
                            Text("View Assets")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .glassEffect(.regular.tint(.accent).interactive())
                                .glassEffectID("View-Assets", in: namespace)
                                .glassEffectTransition(.matchedGeometry)
                                .matchedGeometryEffect(id: "glassCard", in: namespace)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            } else {
                Button(action: {
                    withAnimation {
                        authFlavour = .viewAssets
                    }
                }) {
                    Text("View Assets")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.accent.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .stroke(Color.textPrimary.opacity(0.3), lineWidth: 1)
                                )
                        )
                }
            }


            // Sign Up Button
            Button(action: {
                withAnimation {
                    authFlavour = .createWallet
                }
            }) {
                if #available(iOS 26.0, *) {
                    Text("Create Wallet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .glassEffect(.regular.interactive())
                } else {
                    Text("Create Wallet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(Color.surface.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28)
                                        .stroke(Color.textPrimary.opacity(0.3), lineWidth: 1)
                                )
                        )

                }
            }

            // Sign In Button
            Button(action: {
                withAnimation {
                    authFlavour = .connectWallet
                }
            }) {
                if #available(iOS 26.0, *) {
                    Text("Connect Wallet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .glassEffect(.regular.interactive())
                } else {
                    Text("Connect Wallet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 28)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accent, Color.deepBlue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 160)
        .containerShape(Rectangle())
    }
}
