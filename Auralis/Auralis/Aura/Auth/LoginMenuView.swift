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
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 160)
        .containerShape(Rectangle())
    }
}
