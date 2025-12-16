//
//  AddressTextField.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI

struct AddressTextField: View {
    @Binding var address: String

    var body: some View {
        TextField(
            "Ethereum Address",
            text: $address,
            prompt: Text("0x… or ENS name").foregroundColor(.textSecondary)
        )
        .autocapitalization(.none)
        .disableAutocorrection(true)
        .font(.body)
        .foregroundStyle(Color.textSecondary)
    }
}
