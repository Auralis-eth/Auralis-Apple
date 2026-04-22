//
//  AddressTextField.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI
import UIKit

struct AddressPasteboardValue: Equatable {
    let address: String

    init?(rawValue: String?) {
        guard let trimmed = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }

        self.address = trimmed
    }
}

struct AddressTextField: View {
    @Binding var address: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField(
                "Ethereum Address",
                text: $address,
                prompt: Text("0x… wallet address").foregroundStyle(Color.textSecondary)
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.alphabet)
            .textContentType(.URL)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .focused($isFocused)

            Divider()
                .frame(height: 20)
                .overlay(Color.textSecondary.opacity(0.2))

            Button("Paste", action: pasteAddress)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accent)
                .accessibilityLabel("Paste wallet address")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.textSecondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func pasteAddress() {
        guard let value = AddressPasteboardValue(rawValue: UIPasteboard.general.string) else {
            return
        }

        address = value.address
        isFocused = true
    }
}
