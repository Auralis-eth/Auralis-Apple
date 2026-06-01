import SwiftUI

public struct AuraActionButton: View {
    public enum Style {
        case hero
        case surface
    }

    private let title: String
    private let systemImage: String?
    private let style: Style
    private let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var heroHorizontalPadding: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var heroVerticalPadding: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var surfaceHorizontalPadding: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var surfaceVerticalPadding: CGFloat = 8

    public init(
        _ title: String,
        systemImage: String? = nil,
        style: Style = .surface,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    SystemImage(systemImage)
                        .font(.headline)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: style == .hero ? .infinity : nil, minHeight: 44)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundShape)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var horizontalPadding: CGFloat {
        style == .hero ? heroHorizontalPadding : surfaceHorizontalPadding
    }

    private var verticalPadding: CGFloat {
        style == .hero ? heroVerticalPadding : surfaceVerticalPadding
    }

    @ViewBuilder
    private var backgroundShape: some View {
        switch style {
        case .hero:
            Capsule()
                .fill(Color.accent.gradient)
        case .surface:
            Capsule()
                .fill(Color.deepBlue.opacity(0.35))
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        }
    }
}
