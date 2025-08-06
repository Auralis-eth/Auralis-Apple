//
//  NFTSortButton.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//

import SwiftUI

struct NFTSortButton: View {
    let title: String
    @Binding var sortOrder: SortDescriptor<NFT>
    var keyPath: KeyPath<NFT, String?>

    var body: some View {
        Button {
            if sortOrder.keyPath == keyPath {
                if sortOrder.order == .forward {
                    sortOrder = SortDescriptor(keyPath, order: .reverse)
                } else {
                    sortOrder = SortDescriptor(keyPath, order: .forward)
                }
            } else {
                sortOrder = SortDescriptor(keyPath, order: .forward)
            }
        } label: {
            if sortOrder.keyPath == keyPath {
                    Label(title, systemImage: sortOrder.order == .forward ? "chevron.down" : "chevron.up")
            } else {
                Label(title, systemImage: "basket.fill")
            }
        }
    }
}
