//
//  PasswordField.swift
//  Auralis
//
//  Created by Daniel Bell on 4/18/25.
//

import SwiftUI

struct PasswordField<Field: Hashable>: View {
    @Binding var password: Password
    @Binding var isPasswordValid: Bool
    var placeholder: String
    var field: Field
    var focusedField: FocusState<Field?>.Binding
    @State private var showPassword: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if showPassword {
                    TextField(placeholder, text: $password)
                        .textContentType(.newPassword)
                        .focused(focusedField, equals: field)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.textSecondary)
                } else {
                    SecureField(placeholder, text: $password)
                        .textContentType(.newPassword)
                        .focused(focusedField, equals: field)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.textSecondary)
                }

                Button {
                    showPassword.toggle()
                } label: {
                    SecondaryTextSystemImage(showPassword ? "eye.slash" : "eye")
                }
                .padding(.trailing, 8)
            }

            // Password strength indicator
            HStack {
                SecondaryText("Strength:")
                PasswordStrengthView(strength: password.strength)
            }
            .padding(.top, 5)

            SecondaryCaptionFontText(password.strength.message)
                .lineLimit(nil)
                .accessibilityLabel("Password strength: \(password.strength.rawValue)")
        }
        .onChange(of: password) { _, newValue in
            isPasswordValid = newValue.strength == .strong
        }
    }
}
