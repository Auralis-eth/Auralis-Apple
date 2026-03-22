import SwiftUI

enum AuraSurfaceCardStyle {
    case soft
    case regular
}

struct AuraSurfaceCard<Content: View>: View {
    private let style: AuraSurfaceCardStyle
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: () -> Content

    init(
        style: AuraSurfaceCardStyle = .regular,
        cornerRadius: CGFloat = 30,
        padding: CGFloat = 20,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .modifier(AuraSurfaceGlass(style: style, cornerRadius: cornerRadius))
    }
}

private struct AuraSurfaceGlass: ViewModifier {
    let style: AuraSurfaceCardStyle
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        switch style {
        case .soft:
            content
                .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        case .regular:
            content
                .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AuraSurfaceCard {
            AuraSectionHeader(title: "Regular Surface", subtitle: "Default glass treatment")
            SecondaryText("Used for utility cards and empty states.")
        }

        AuraSurfaceCard(style: .soft, cornerRadius: 25) {
            AuraSectionHeader(title: "Soft Surface")
            SecondaryText("Used for Home tiles and scenic modules.")
        }
    }
    .padding()
    .background(Color.background)
    .preferredColorScheme(.dark)
}
