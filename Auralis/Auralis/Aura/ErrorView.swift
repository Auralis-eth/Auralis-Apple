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

struct RouteErrorScreen: View {
    let routeError: AppRouteError
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SystemImage("exclamationmark.triangle.fill")
                            .foregroundStyle(Color.error)
                        HeadlineFontText(routeError.title)
                    }

                    SecondaryText(routeError.message)
                        .font(.body)

                    if let urlString = routeError.urlString {
                        SecondaryCaptionFontText(urlString)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .glassEffect(.regular.tint(.error.opacity(0.2)), in: .rect(cornerRadius: 16))

                Button("Dismiss") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("routeError.dismiss")

                Spacer()
            }
            .padding()
            .navigationTitle("Routing Error")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("routeError.screen")
        }
    }
}
