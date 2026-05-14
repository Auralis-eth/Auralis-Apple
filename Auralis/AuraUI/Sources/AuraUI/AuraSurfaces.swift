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
            .modifier(AuraSurfaceGlass(style: style, cornerRadius: cornerRadius))
    }
}

private struct AuraSurfaceGlass: ViewModifier {
    let style: AuraSurfaceCardStyle
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
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
                .background(Color.surface.opacity(style == .soft ? 0.45 : 0.7), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
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
    }
}

public extension AuraSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}
