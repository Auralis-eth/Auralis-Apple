//
//  PasswordEntryView.swift
//  Auralis
//
//  Created by Daniel Bell on 5/7/25.
//

import SwiftUI


struct PasswordEntryView: View {
    enum Field {
        case password, confirmPassword
    }

    @Binding var passwordIsValid: Bool
    @Binding var errorMessage: String
    @Binding var password: Password
    @State private var confirmPassword: Password = ""
    @State private var isPasswordValid: Bool = false
    @FocusState private var focusedField: Field?
    private var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 5) {
                SecondaryText("Enter Password")
                    .fontWeight(.medium)

                PasswordField(
                    password: $password,
                    isPasswordValid: $isPasswordValid,
                    placeholder: "Password",
                    field: .password,
                    focusedField: $focusedField
                )
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 5) {
                SecondaryText("Confirm Password")
                    .fontWeight(.medium)

                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirmPassword)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundStyle(Color.textSecondary)
                    .disabled(password.isEmpty)


                if !confirmPassword.isEmpty && !passwordsMatch {
                    ErrorText("Passwords do not match")
                        .accessibilityLabel("Error: Passwords do not match")
                }

                if !errorMessage.isEmpty {
                    ErrorText(errorMessage)
                        .accessibilityLabel("Error: \(errorMessage)")
                }
            }
            .padding(.horizontal)

            CalloutFontText("⚠️ This password is not recoverable. If you lose it, you will lose access to your wallet.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .onChange(of: isPasswordValid && passwordsMatch) { oldValue, newValue in
            passwordIsValid = newValue
        }
    }
}
