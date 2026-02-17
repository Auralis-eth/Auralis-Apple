//
//  GatewayView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI

struct GatewayView: View {
    @Binding var currentAccount: EOAccount?

    var body: some View {
        AddressInputView(
            currentAccount: $currentAccount
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GatewayBackgroundImage()
                .ignoresSafeArea()

            Color.background.opacity(0.3)
                .ignoresSafeArea()
        }
    }
}
