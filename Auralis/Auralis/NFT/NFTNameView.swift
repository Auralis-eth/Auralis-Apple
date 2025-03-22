//
//  NFTNameView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI

//struct NFTNameView: View {
//    let name: String?
//    let arworkName: String?
//    let metaCollectionName: String?
//    let artist: String?
//    let createdBy: String?
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 4) {
//            if let metaCollectionName {
//                Text("Collection: " + metaCollectionName)
//                    .font(.subheadline)
//                    .fontWeight(.semibold)
//                    .lineLimit(2)
//                    .foregroundColor(.secondary)
//            }
//
//            if let name = name ?? arworkName {
//                Text("Name: " + name)
//                    .font(.headline)
//                    .fontWeight(.semibold)
//                    .lineLimit(2)
//            }
//
//
//            if let artist = artist ?? createdBy {
//                Text("Artist: " + artist)
//                    .font(.headline)
//                    .fontWeight(.semibold)
//                    .lineLimit(2)
//            }
//        }
//        .padding(.vertical, 8)
//        .padding(.horizontal, 12)
//    }
//}

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
                        .foregroundColor(.secondary)
                }

                if let artworkName = displayName, !artworkName.isEmpty {
                    Text(artworkName)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundColor(.primary)
                }

                if let artistName = displayArtist, !artistName.isEmpty {
                    HStack(spacing: 4) {
                        Text("by")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundColor(.secondary)
                            .italic()

                        Text(artistName)
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .foregroundColor(.primary)
                    }
                }
            }
            Spacer()
        }

    }
}
