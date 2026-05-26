import SwiftUI

public struct AuraPill: View {
    public enum Emphasis {
        case neutral
        case accent
        case success
    }

    private let title: String?
    private let systemImage: String?
    private let emphasis: Emphasis
    private let imageSize: Font
    private let label: String?
    private let isAccessibilityHidden: Bool

    /// Use for pills with visible text. Pass `accessibilityLabel` only when the visible text needs more context.
    public init(
        _ title: String,
        systemImage: String? = nil,
        emphasis: Emphasis = .neutral,
        imageSize: Font = .caption,
        accessibilityLabel: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.emphasis = emphasis
        self.imageSize = imageSize
        self.label = accessibilityLabel ?? title
        self.isAccessibilityHidden = false
    }

    /// Use for icon-only pills that communicate meaningful status.
    public init(
        systemImage: String,
        emphasis: Emphasis = .neutral,
        imageSize: Font = .caption,
        accessibilityLabel: String
    ) {
        self.title = nil
        self.systemImage = systemImage
        self.emphasis = emphasis
        self.imageSize = imageSize
        self.label = accessibilityLabel
        self.isAccessibilityHidden = false
    }

    /// Use only when the icon-only pill is decorative and repeated elsewhere in accessible text.
    public init(
        systemImage: String,
        emphasis: Emphasis = .neutral,
        imageSize: Font = .caption,
        decorative: Bool
    ) {
        self.title = nil
        self.systemImage = systemImage
        self.emphasis = emphasis
        self.imageSize = imageSize
        self.label = nil
        self.isAccessibilityHidden = true
    }

    public var body: some View {
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
        .accessibilityLabel(label ?? "")
        .accessibilityHidden(isAccessibilityHidden)
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

public enum AuraUntrustedValueKind: String, Equatable, Sendable {
    case metadata
    case provider
    case link
    case scan
    case deepLink

    public var title: String {
        switch self {
        case .metadata:
            return "Untrusted metadata"
        case .provider:
            return "Provider-backed value"
        case .link:
            return "Untrusted link"
        case .scan:
            return "Untrusted scan"
        case .deepLink:
            return "Untrusted deep link"
        }
    }

    public var accessibilityLabel: String {
        "\(title). Treat this value as externally supplied until verified."
    }
}

public struct AuraTrustLabel: View {
    private let kind: AuraUntrustedValueKind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var iconSize = 10.0

    public init(kind: AuraUntrustedValueKind) {
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: iconSize, weight: .bold))
                .accessibilityHidden(true)

            Text(kind.title)
                .font(.caption.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(red: 0.97, green: 0.8, blue: 0.38))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 0.58, green: 0.37, blue: 0.08).opacity(0.28))
        )
        .overlay {
            Capsule()
                .stroke(Color(red: 0.97, green: 0.8, blue: 0.38).opacity(0.4), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.accessibilityLabel)
    }
}
