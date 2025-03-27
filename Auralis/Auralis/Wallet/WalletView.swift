//
//  WalletView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import SwiftUI

// MARK: - Main WalletView
struct WalletView: View {
    @Binding var account: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Address bar at the top
                AddressBarView(address: $account)
                Spacer()
            }
            .padding(.horizontal)
            .background(Color.background)
        }
    }
}
