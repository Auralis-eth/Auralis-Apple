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
            prompt: Text("0x… wallet address").foregroundColor(.textSecondary)
        )
        .autocapitalization(.none)
        .disableAutocorrection(true)
        .font(.body)
        .foregroundStyle(Color.textSecondary)
    }
}
