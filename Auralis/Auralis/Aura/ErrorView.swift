//
//  ErrorView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import SwiftUI

struct ErrorView: View {
    let action: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SystemImage("exclamationmark.triangle.fill")
                    .foregroundStyle(Color.error)
                HeadlineFontText("Error")
            }

            SecondaryText("An unknown error occurred. Please check your connection and try again.")
                .font(.body)

            Button {
                action()
            } label: {
                PrimaryText("Try Again")
                    .fontWeight(.medium)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.accent)
                    .cornerRadius(8)
            }
            .padding(.top, 8)

        }
        .padding()
        .glassEffect(.regular.tint(.error.opacity(0.2)), in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}
