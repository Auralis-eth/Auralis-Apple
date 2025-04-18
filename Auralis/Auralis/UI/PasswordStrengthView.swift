//
//  PasswordStrengthView.swift
//  Auralis
//
//  Created by Daniel Bell on 4/14/25.
//

import SwiftUI


struct PasswordStrengthView: View {
    enum PasswordStrength {
        case weak, medium, strong
        var message: String {
            switch self {
            case .weak:
                return "Use at least 8 characters with numbers, symbols, and mixed case letters."
            case .medium:
                return "Good password, but consider adding more complexity."
            case .strong:
                return "Strong password!"
            }
        }
    }

    let strength: PasswordStrength

    var body: some View {
        HStack(spacing: 2) {
            Rectangle()
                .frame(height: 5)
                .foregroundColor(strengthColor(for: .weak))

            Rectangle()
                .frame(height: 5)
                .foregroundColor(strengthColor(for: .medium))

            Rectangle()
                .frame(height: 5)
                .foregroundColor(strengthColor(for: .strong))
        }
        .frame(width: 100)
    }

    private func strengthColor(for level: PasswordStrength) -> Color {
        switch (level, strength) {
        case (.weak, .weak), (.medium, .weak), (.strong, .weak):
            return .red
        case (.medium, .medium), (.strong, .medium):
            return .orange
        case (.strong, .strong):
            return .green
        default:
            return Color.gray.opacity(0.3)
        }
    }
}

