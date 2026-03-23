import SwiftUI

struct AuraPill: View {
    enum Emphasis {
        case neutral
        case accent
        case success
    }

    private let title: String?
    private let systemImage: String?
    private let emphasis: Emphasis
    private let imageSize: Font
    private let accessibilityLabel: String?

    init(_ title: String? = nil, systemImage: String? = nil, emphasis: Emphasis = .neutral, imageSize: Font = .caption, accessibilityLabel: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.emphasis = emphasis
        self.imageSize = imageSize
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                SystemImage(systemImage)
                    .font(imageSize)
                    .accessibilityHidden(true)
            }

            if let title {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title ?? accessibilityLabel ?? "")
    }

    private var foregroundColor: Color {
        switch emphasis {
        case .neutral, .accent:
            return .textPrimary
        case .success:
            return .success
        }
    }

    private var backgroundColor: Color {
        switch emphasis {
        case .neutral:
            return Color.deepBlue.opacity(0.18)
        case .accent:
            return Color.accent.opacity(0.22)
        case .success:
            return Color.success.opacity(0.16)
        }
    }

    private var borderColor: Color {
        switch emphasis {
        case .neutral:
            return .white.opacity(0.18)
        case .accent:
            return .white.opacity(0.22)
        case .success:
            return .success.opacity(0.35)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        AuraPill("Ethereum")
        AuraPill("Live", systemImage: "sparkles", emphasis: .accent)
        AuraPill("Loaded", systemImage: "checkmark.circle.fill", emphasis: .success)
    }
    .padding()
    .background(Color.background)
    .preferredColorScheme(.dark)
}
