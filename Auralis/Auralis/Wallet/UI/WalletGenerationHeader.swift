//
//  WalletGenerationHeader.swift
//  Auralis
//
//  Created by Daniel Bell on 5/6/25.
//

import SwiftUI

struct WalletGenerationHeader: View {
    enum Action {
        case importWallet
        case createWallet
        var title: String {
            switch self {
                case .importWallet:
                    return "Import Wallet"
                case .createWallet:
                    return "Create a New Wallet"
            }
        }
    }
    @Environment(\.dismiss) var dismiss
    let action: Action
    var body: some View {
        HStack {
            Spacer()
            TitleFontText(text: action.title)
            Spacer()
        }
        .background(Color.background)
        .overlay {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    SecondaryTextSystemImage("xmark")
                }
                .accessibilityLabel("Close")
            }
            .padding(.trailing)
        }
    }
}
