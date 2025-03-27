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
