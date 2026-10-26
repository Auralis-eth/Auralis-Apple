import AuraUI
import SwiftUI

struct NFTLibraryScenicScreen<Content: View>: View {
    var horizontalPadding: CGFloat = 20
    var verticalPadding: CGFloat = 20
    var contentAlignment: Alignment = .top
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: contentAlignment) {
            Color.background
                .ignoresSafeArea()

            content
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
        }
    }
}

struct NFTLibraryBadgeLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surface.opacity(0.65), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.textSecondary.opacity(0.18), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
    }
}

struct NFTLibraryGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content
                .background(Color.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
