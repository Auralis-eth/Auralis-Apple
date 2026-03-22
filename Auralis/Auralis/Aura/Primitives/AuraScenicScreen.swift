import SwiftUI

struct AuraScenicScreen<Content: View>: View {
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let contentAlignment: Alignment
    private let content: () -> Content

    init(
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 16,
        contentAlignment: Alignment = .top,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.contentAlignment = contentAlignment
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
            .safeAreaPadding(.horizontal, horizontalPadding)
            .safeAreaPadding(.vertical, verticalPadding)
            .background {
                GatewayBackgroundImage()
                    .ignoresSafeArea()

                Color.background.opacity(0.3)
                    .ignoresSafeArea()
            }
    }
}

#Preview {
    AuraScenicScreen {
        VStack(spacing: 16) {
            AuraSurfaceCard {
                AuraSectionHeader(title: "Gateway")

                SecondaryText("Scenic shell preview")
            }

            AuraSurfaceCard(style: .soft) {
                AuraSectionHeader(title: "Modules", subtitle: "Same scenic stage, lighter surface")
            }
        }
    }
}
