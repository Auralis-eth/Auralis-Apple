//
//  NFFTDescriptionView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI

struct NFTDescriptionView: View {
    var description: String
    var body: some View {
        Card3D(cardColor: .surface) {
            SystemFontText(
                text: description,
                size: 15,
                weight: .medium
            )
            .lineLimit(5)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
        }
    }
}
