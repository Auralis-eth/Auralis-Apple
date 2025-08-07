//
//  LoginView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI

struct LoginView: View {
    enum AuthFlavor {
        case viewAssets
        case menu
    }

    @Binding var currentAccount: EOAccount?
    @State private var authFlavor: AuthFlavor = .menu
    @State private var isAddressExpanded: Bool = false //will need to become a focus

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                LoginTitleView()
                    .padding(.bottom, 40)

                LoginMenuView(authFlavour: $authFlavor, currentAccount: $currentAccount, isAddressExpanded: $isAddressExpanded)

            }
            .background {
                Image("aurora-1") // Replace with your background image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .overlay {
                        Color.background.opacity(0.3)
                            .ignoresSafeArea()
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isAddressExpanded = false
                }
            }
        }
    }
}
