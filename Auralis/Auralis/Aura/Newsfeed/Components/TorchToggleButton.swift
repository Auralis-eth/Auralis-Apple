//
//  TorchToggleButton.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//

import SwiftUI
import AuraUI

struct TorchToggleButton: View {
    @Binding var torchOn: Bool

    var body: some View {
        Button {
            torchOn.toggle()
        } label: {
            HStack {
                SystemImage(torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title2)
                    .foregroundStyle(torchOn ? .accent : Color.secondary)
                PrimaryText(torchOn ? "Torch Off" : "Torch On")
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glass) // Apply custom button style for subtle animation
        .tint(.surface.opacity(0.5))
        .accessibilityLabel(String(localized: "Torch"))
        .accessibilityValue(torchOn ? String(localized: "On") : String(localized: "Off"))
        .accessibilityHint(
            torchOn
                ? String(localized: "Turns the torch off")
                : String(localized: "Turns the torch on")
        )
    }
}
