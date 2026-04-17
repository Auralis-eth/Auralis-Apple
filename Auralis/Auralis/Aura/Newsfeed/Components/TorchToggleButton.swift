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
                    .foregroundStyle(torchOn ? Color.secondary : .accent) // Use yellow when on, gray when off
                PrimaryText(torchOn ? "Torch Off" : "Torch On")
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glass) // Apply custom button style for subtle animation
        .tint(.surface.opacity(0.5))
    }
}
