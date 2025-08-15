//
//  GatewayView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI

struct GatewayView: View {
    @Binding var currentAccount: EOAccount?
    @State private var isAddressExpanded: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            GatewayBackgroundImage()
            Color.background.opacity(0.3)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isAddressExpanded = false
                    }
                }
            VStack(spacing: 40) {
                LoginTitleView()

                AccountAccessView(
                    currentAccount: $currentAccount,
                    isAddressExpanded: $isAddressExpanded
                )
            }
        }
    }
}

struct GatewayBackgroundImage: View {
    var body: some View {
        Image("aurora-1")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
    }
}
