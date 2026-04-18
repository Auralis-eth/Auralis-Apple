//
//  NFTSortButton.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//

import SwiftUI

struct NFTSortButton: View {
    enum Field: String {
        case acquired
        case collectionName
        case itemName

        func descriptor(order: SortOrder = .forward) -> SortDescriptor<NFT> {
            switch self {
            case .acquired:
                SortDescriptor(\NFT.acquiredAt?.blockTimestamp, order: order)
            case .collectionName:
                SortDescriptor(\NFT.collection?.name, order: order)
            case .itemName:
                SortDescriptor(\NFT.name, order: order)
            }
        }
    }

    let title: String
    let field: Field
    @Binding var sortOrder: SortDescriptor<NFT>

    var body: some View {
        Button {
            if sortOrder.keyPath == field.descriptor().keyPath {
                if sortOrder.order == .forward {
                    sortOrder = field.descriptor(order: .reverse)
                } else {
                    sortOrder = field.descriptor(order: .forward)
                }
            } else {
                sortOrder = field.descriptor(order: .forward)
            }
        } label: {
            if sortOrder.keyPath == field.descriptor().keyPath {
                    Label(title, systemImage: sortOrder.order == .forward ? "chevron.down" : "chevron.up")
            } else {
                Label(title, systemImage: "basket.fill")
            }
        }
    }
}
