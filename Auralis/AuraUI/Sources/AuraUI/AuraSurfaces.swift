import SwiftUI

public enum AuraSurfaceCardStyle {
    case soft
    case regular
}

public struct AuraSurfaceCard<Content: View>: View {
    private let style: AuraSurfaceCardStyle
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: () -> Content

    public init(
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

    public var body: some View {
        content()
            .padding(padding)
            .auraSurfaceBackground(style: style, cornerRadius: cornerRadius)
    }
}

public extension View {
    func auraSurfaceBackground(
        style: AuraSurfaceCardStyle = .regular,
        cornerRadius: CGFloat = 30
    ) -> some View {
        modifier(AuraSurfaceGlass(style: style, cornerRadius: cornerRadius))
    }
}

private struct AuraSurfaceGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let style: AuraSurfaceCardStyle
    let cornerRadius: CGFloat

    private var needsOpaqueSurface: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if needsOpaqueSurface {
            content
                .background(Color(.secondarySystemBackground), in: shape)
                .overlay {
                    shape.strokeBorder(Color(.separator), lineWidth: 1)
                }
        } else if #available(iOS 26, macOS 26, *) {
            switch style {
            case .soft:
                content
                    .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            case .regular:
                content
                    .glassEffect(.regular.tint(.surface), in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
                .background(Color.surface.opacity(style == .soft ? 0.45 : 0.7), in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
        }
    }
}

public struct AuraSectionHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
            ViewThatFits(in: .vertical) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    titleView
                    trailing
                }

                VStack(alignment: .leading, spacing: 8) {
                    titleView
                    trailing
                }
            }

            if let subtitle, !subtitle.isEmpty {
                SecondaryText(subtitle)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var titleView: some View {
        SubheadlineFontText(title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .accessibilityAddTraits(.isHeader)
    }
}

public extension AuraSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}
