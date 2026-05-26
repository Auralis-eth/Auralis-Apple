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

    func auraAccessibleSummary(label: String, value: String? = nil, hint: String? = nil) -> some View {
        modifier(AuraAccessibleSummary(label: label, value: value, hint: hint))
    }
}

private struct AuraAccessibleSummary: ViewModifier {
    let label: String
    let value: String?
    let hint: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        let summarizedContent = content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value ?? "")

        if let hint, !hint.isEmpty {
            summarizedContent
                .accessibilityHint(hint)
        } else {
            summarizedContent
        }
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
                .background(Color.surface, in: shape)
                .overlay {
                    shape.strokeBorder(Color.separator, lineWidth: 1)
                }
        } else {
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
        HeadlineFontText(title)
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
