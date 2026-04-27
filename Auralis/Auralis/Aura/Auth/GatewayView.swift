//
//  GatewayView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI

struct GatewayView: View {
    let ensResolver: any ENSResolving
    let services: ShellServiceHub
    let onAccountActivated: @MainActor (EOAccount, String?) -> Void

    var body: some View {
        AuraScenicScreen(contentAlignment: .center) {
            AddressInputView(
                ensResolver: ensResolver,
                accountStoreFactory: services.accountStoreFactory,
                onAccountActivated: onAccountActivated
            )
        }
    }
}
