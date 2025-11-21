//
//  AccountAccessView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI

struct AccountAccessView: View {
    @Binding var currentAccount: EOAccount?

    var body: some View {
        GlassEffectContainer(spacing: 10.0) {
            AddressInputView(currentAccount: $currentAccount)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 160)
    }
}
