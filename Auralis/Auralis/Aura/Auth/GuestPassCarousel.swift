//
//  GuestPassCarousel.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI

struct GuestPassCarousel: View {
    let items: [DemoAccount]
    let select: (DemoAccount) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(items) { acct in
                    GuestPassCard(account: acct) {
                        select(acct)
                    }
                    .frame(width: 275)
                    .accessibilityLabel(Text("Opens Auralis with a demo account: " + acct.title))
                }
                .padding(.vertical)
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 12, for: .scrollContent)
        .padding(.horizontal, 15)
        .padding(.vertical, 18)
    }
}
