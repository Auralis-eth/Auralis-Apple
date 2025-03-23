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
                    Text(collection)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundColor(.textSecondary)
                }

                if let artworkName = displayName, !artworkName.isEmpty {
                    Text(artworkName)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundColor(.textPrimary)
                }

                if let artistName = displayArtist, !artistName.isEmpty {
                    HStack(spacing: 4) {
                        Text("by")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundColor(.textSecondary)
                            .italic()

                        Text(artistName)
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundColor(.accent)
                    }
                }
            }
            Spacer()
        }
    }
}
