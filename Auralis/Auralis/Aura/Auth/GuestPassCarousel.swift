import SwiftUI

struct GuestPassCarousel: View {
    let items: [GuestPassAccount]
    let select: (GuestPassAccount) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(items) { account in
                    GuestPassCard(account: account) {
                        select(account)
                    }
                    .frame(width: 275)
                    .accessibilityLabel(Text("Opens Auralis with a guest pass account: " + account.title))
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
