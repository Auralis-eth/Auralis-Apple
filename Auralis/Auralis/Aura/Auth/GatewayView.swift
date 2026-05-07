//
//  GatewayView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import AuralisPrimaryModels
import SwiftUI

struct GatewayView: View {
    let dependencies: GatewayDependencies
    let onAccountActivated: @MainActor (EOAccount, String?) -> Void

    var body: some View {
        AuraScenicScreen(contentAlignment: .center) {
            AddressInputView(
                ensResolver: dependencies.ensResolver,
                accountStoreFactory: dependencies.accountStoreFactory,
                onAccountActivated: onAccountActivated
            )
        }
    }
}
