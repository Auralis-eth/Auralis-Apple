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
                    .lineLimit(2)
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
    }

    private var horizontalPadding: CGFloat {
        style == .hero ? 20 : 16
    }

    private var verticalPadding: CGFloat {
        style == .hero ? 18 : 8
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
