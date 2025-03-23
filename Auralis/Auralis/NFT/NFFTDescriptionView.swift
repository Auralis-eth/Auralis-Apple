//
//  NFFTDescriptionView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI

struct NFFTDescriptionView: View {
    var description: String
    var body: some View {
        Card3D(cardColor: .surface) {
            Text(description)
                .lineLimit(5)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .foregroundColor(.textPrimary)
                .font(.system(size: 15, weight: .medium, design: .serif))
        }
    }
}
