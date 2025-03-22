//
//  EthereumKeyStoreSelectorView.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import SwiftUI

struct EthereumKeyStoreSelectorView: View {
    @Binding var selectedKeystore: EthereumKeyStore?
    var keystores: [EthereumKeyStore]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ForEach(keystores) { keystore in
            HStack {
                Text(keystore.nickName ?? "--")
                Spacer()
                Text("addresses: ") + Text("\(keystore.addresses.count)")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedKeystore = keystore
                dismiss()
            }
        }
    }
}
//#Preview {
//    EthereumKeyStoreSelectorView()
//}
