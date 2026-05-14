import SwiftUI

public enum AuraFeedbackTone: Equatable {
    case neutral
    case warning
    case critical

    var tintColor: Color {
        switch self {
        case .neutral:
            return .accent
        case .warning:
            return .orange
        case .critical:
            return .error
        }
    }

    var secondaryTintColor: Color {
        switch self {
        case .neutral:
            return .textSecondary
        case .warning:
            return Color.orange.opacity(0.9)
        case .critical:
            return Color.error.opacity(0.9)
        }
    }
}

public struct AuraFeedbackAction {
    public let title: String
    public let systemImage: String
    public let handler: () -> Void

    public init(title: String, systemImage: String, handler: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.handler = handler
    }
}

public struct AuraEmptyState: View {
    public let eyebrow: String?
    public let title: String
    public let message: String
    public let systemImage: String
    public let tone: AuraFeedbackTone
    public let primaryAction: AuraFeedbackAction?
    public let secondaryAction: AuraFeedbackAction?

    public init(
        eyebrow: String? = nil,
        title: String,
        message: String,
        systemImage: String,
        tone: AuraFeedbackTone = .neutral,
        primaryAction: AuraFeedbackAction? = nil,
        secondaryAction: AuraFeedbackAction? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 30, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    SystemImage(systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tone.tintColor)
                        .frame(width: 36, height: 36)
                        .background(tone.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 8) {
                        if let eyebrow, !eyebrow.isEmpty {
                            Text(eyebrow.uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tone.secondaryTintColor)
                        }

                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if primaryAction != nil || secondaryAction != nil {
                    HStack(spacing: 10) {
                        if let primaryAction {
                            AuraActionButton(primaryAction.title, systemImage: primaryAction.systemImage, style: .surface) {
                                primaryAction.handler()
                            }
                        }

                        if let secondaryAction {
                            AuraActionButton(secondaryAction.title, systemImage: secondaryAction.systemImage, style: .surface) {
                                secondaryAction.handler()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

public struct AuraErrorBanner: View {
    public let title: String
    public let message: String
    public let systemImage: String
    public let tone: AuraFeedbackTone
    public let action: AuraFeedbackAction?

    public init(
        title: String,
        message: String,
        systemImage: String,
        tone: AuraFeedbackTone = .warning,
        action: AuraFeedbackAction? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SystemImage(systemImage)
                .font(.headline)
                .foregroundStyle(tone.tintColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 8)

            if let action {
                Button(action: action.handler) {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tone.tintColor.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
