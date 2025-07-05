//
//  ReadOnlyAddressInput.swift
//  Auralis
//
//  Created by Daniel Bell on 4/30/25.
//

import SwiftUI

struct ReadOnlyAddressInput: View {
    @State private var address: String = ""
    @State private var isAddressValid: Bool = false
    var onSubmit: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("Enter Ethereum address (0x...)", text: $address)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.body)  // Use your desired font
                .scrollContentBackground(.hidden)
                .foregroundStyle(Color.textPrimary)
                .padding()
                .background(Color.surface.opacity(0.1))
                .cornerRadius(8)
                .onChange(of: address) { _, newValue in
                    validateAddress(newValue)
                }


            Button {
                onSubmit(address)
            } label: {
                SecondaryText("Add Address")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isAddressValid ? Color.accent : Color.surface)
                    .cornerRadius(10)
            }
            .disabled(!isAddressValid)
        }
        .background {
            Color.surface
        }
    }

    private func validateAddress(_ address: String) {
        // Simple validation - should be 42 chars with 0x prefix
        isAddressValid = address.count == 42 && address.hasPrefix("0x")
    }
}

