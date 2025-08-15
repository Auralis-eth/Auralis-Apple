//
//  AccountAccessView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI

struct AccountAccessView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var isAddressExpanded: Bool
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer(spacing: 10.0) {
            if isAddressExpanded {
                AddressInputView(currentAccount: $currentAccount)
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
                }
                .transition(.scale.combined(with: .opacity))
                .buttonStyle(.glassProminent)
                .tint(.accent)
                .glassEffectID("View-Assets", in: namespace)
                .glassEffectTransition(.matchedGeometry)
                .matchedGeometryEffect(id: "glassCard", in: namespace)

            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 160)
        .containerShape(Rectangle())
    }
}
