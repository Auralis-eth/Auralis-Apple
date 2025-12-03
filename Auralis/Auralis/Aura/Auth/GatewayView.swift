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
        ZStack(alignment: .bottom) {
            
            GatewayBackgroundImage()
            
            Color.background.opacity(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                
                LoginTitleView()
                
                VStack {
                    Text("Your personal aurora of sound, motion, and on-chain life")
                    Text("Welcome. To visualize your soundscape, we need a signal.")
                }
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .kerning(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                
                AccountAccessView(
                    currentAccount: $currentAccount
                )
                
            }
        }
    }
}
