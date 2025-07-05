//
//  NFTNewsfeedLoadingView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import SwiftUI

struct NFTNewsfeedLoadingView: View {
    enum Size {
        case large
        case small
    }

    let itemsLoaded: Int?
    let total: Int?
    var size: Size = .large

    var body: some View {
        if #available(iOS 26.0, *) {
            VStack {
                if size == .large {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                        .padding(.top)
                }
                HeadlineFontText("Loading NFTs...")
                    .padding(.top, 16)
                LoadingProgressView(total: total, itemsLoaded: itemsLoaded)
            }
            .padding(.vertical)
            .frame(maxWidth: size == .large ? .infinity : 200)
            .glassEffect(.regular.tint(.surface.opacity(0.2)), in: .rect(cornerRadius: 32))
        } else {
            Card3D(cardColor: .surface) {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: .secondary))

                    HeadlineFontText("Loading NFTs...")
                        .padding(.top, 16)
                    Card3D(cardColor: .surface) {
                        LoadingProgressView(total: total, itemsLoaded: itemsLoaded)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
