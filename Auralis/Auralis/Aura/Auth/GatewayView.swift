//
//  GatewayView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI

struct GatewayView: View {
    @Binding var currentAccount: EOAccount?
    let ensResolver: any ENSResolving
    let services: ShellServiceHub

    var body: some View {
        AuraScenicScreen(contentAlignment: .center) {
            AddressInputView(
                currentAccount: $currentAccount,
                ensResolver: ensResolver,
                accountStoreFactory: services.accountStoreFactory
            )
        }
    }
}
