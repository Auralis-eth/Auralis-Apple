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
        AuraScenicScreen(contentAlignment: .center) {
            VStack(spacing: 16) {
                ShellFirstRunStateView()

                AddressInputView(
                    currentAccount: $currentAccount
                )
            }
        }
    }
}
