//
//  NFTNameView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI

struct NFTNameView: View {
    let name: String?
    let arworkName: String?
    let metaCollectionName: String?
    let artist: String?
    let createdBy: String?

    private var displayName: String? {
        name ?? arworkName
    }

    private var displayArtist: String? {
        artist ?? createdBy
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                if let collection = metaCollectionName, !collection.isEmpty {
                    SystemFontText(text: collection, size: 14, weight: .medium)
                }

                if let artworkName = displayName, !artworkName.isEmpty {
                    SystemFontText(text: artworkName, size: 18, weight: .semibold)
                }

                if let artistName = displayArtist, !artistName.isEmpty {
                    HStack(spacing: 4) {
                        SystemFontText(text: "by", size: 14, weight: .regular)
                            .italic()

                        SystemFontText(text: artistName, size: 15, weight: .medium)
                    }
                }
            }
            Spacer()
        }
    }
}
