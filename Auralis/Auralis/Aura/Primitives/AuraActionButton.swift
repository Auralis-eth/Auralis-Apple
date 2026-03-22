import SwiftUI

struct AuraActionButton: View {
    enum Style {
        case hero
        case surface
    }

    private let title: String
    private let systemImage: String?
    private let style: Style
    private let action: () -> Void

    init(
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

    var body: some View {
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
            .foregroundStyle(foregroundStyle)
            .frame(maxWidth: style == .hero ? .infinity : nil)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundShape)
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .accessibilityLabel(title)
    }

    private var foregroundStyle: Color {
        Color.textPrimary
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .hero:
            return 20
        case .surface:
            return 16
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .hero:
            return 18
        case .surface:
            return 8
        }
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

#Preview {
    VStack(spacing: 20) {
        AuraActionButton("Enter Auralis", style: .hero) {}

        AuraActionButton("Open player", systemImage: "play.fill") {}
    }
    .padding()
    .background(Color.background)
    .preferredColorScheme(.dark)
}
