//
//  TorchToggleButton.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//

import SwiftUI

struct TorchToggleButton: View {
    @Binding var torchOn: Bool

    var body: some View {
        Button {
            torchOn.toggle()
        } label: {
            HStack {
                SystemImage(torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title2)
                    .foregroundColor(torchOn ? .secondary : .deepBlue) // Use yellow when on, gray when off
                PrimaryText(torchOn ? "Torch Off" : "Torch On")
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surface) // Use system background for adaptive colors
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(ScaleButtonStyle()) // Apply custom button style for subtle animation
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
