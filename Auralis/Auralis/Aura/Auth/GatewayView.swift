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
        VStack {
            
//            LoginTitleView()
//            VStack {
//                Spacer()
//                Text("Connect a signal to reveal your personal on-chain aurora.")//living
//                    .font(.subheadline)
//                    .foregroundStyle(Color.textPrimary)
//                    .kerning(2)
//                    .multilineTextAlignment(.center)
//                    .fixedSize(horizontal: false, vertical: true)
//                    .padding(.horizontal, 30)
//                
//                Spacer()
//            }
            AccountAccessView(
                currentAccount: $currentAccount
            )
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GatewayBackgroundImage()
                .ignoresSafeArea()

            Color.background.opacity(0.3)
                .ignoresSafeArea()
        }
    }
}
