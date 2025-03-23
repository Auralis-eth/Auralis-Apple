//
//  Card3D.swift
//  Auralis
//
//  Created by Daniel Bell on 3/17/25.
//


import SwiftUI

struct Card3D<Content: View>: View {
    var content: () -> Content

    // Customization properties
    var cornerRadius: CGFloat = 16
    var shadowRadius: CGFloat = 10
    var cardColor: Color = .surface
    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color.surface, cardColor.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    init(cardColor: Color = .surface, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.cardColor = cardColor
    }

    var body: some View {
        content()
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // Base card with gradient
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(backgroundGradient)

                    // Subtle border for depth
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [Color.accent.opacity(0.6), Color.accent.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )

                    // Highlight on top edge
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.secondary.opacity(0.8), Color.secondary.opacity(0)],
                                startPoint: .topLeading,
                                endPoint: .center
                            ),
                            lineWidth: 1.5
                        )
                        .mask(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(lineWidth: 2)
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.2), radius: shadowRadius, x: 5, y: 5)
            .shadow(color: Color.deepBlue.opacity(0.1), radius: shadowRadius/2, x: 2, y: 2)
            // Small scale effect to enhance 3D appearance
            .scaleEffect(0.98)
    }
}

// Usage example
struct ContentView: View {
    var body: some View {
        ZStack {
            // Background color
            Color.background
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Horizontal card
                Card3D() {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.accent)

                        VStack(alignment: .leading) {
                            Text("Premium Card")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            Text("Tap to view details")
                                .font(.subheadline)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                }

                // Vertical card
                Card3D(cardColor: .deepBlue.opacity(0.7)) {
                    VStack(spacing: 15) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)

                        Text("Special Offer")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)

                        Text("Limited time only")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .padding()
                }

                // Custom styled card
                Card3D(cardColor: .accent.opacity(0.5)) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Premium Account")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            Text("$99/month")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            Text("Unlimited access to all features")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}
