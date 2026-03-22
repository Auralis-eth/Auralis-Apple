import SwiftUI

enum AuraFeedbackTone {
    case neutral
    case warning
    case critical

    var tintColor: Color {
        switch self {
        case .neutral:
            return .accent
        case .warning:
            return Color.orange
        case .critical:
            return .error
        }
    }

    var secondaryTintColor: Color {
        switch self {
        case .neutral:
            return Color.textSecondary
        case .warning:
            return Color.orange.opacity(0.9)
        case .critical:
            return Color.error.opacity(0.9)
        }
    }
}

struct AuraFeedbackAction {
    let title: String
    let systemImage: String
    let handler: () -> Void
}

struct AuraEmptyState: View {
    let eyebrow: String?
    let title: String
    let message: String
    let systemImage: String
    let tone: AuraFeedbackTone
    let primaryAction: AuraFeedbackAction?
    let secondaryAction: AuraFeedbackAction?

    init(
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

    var body: some View {
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

#Preview {
    AuraScenicScreen(contentAlignment: .center) {
        AuraEmptyState(
            eyebrow: "Library",
            title: "Nothing Here Yet",
            message: "This reusable empty state is intended for shell and feature surfaces alike.",
            systemImage: "square.stack.3d.up",
            tone: .neutral,
            primaryAction: AuraFeedbackAction(
                title: "Refresh",
                systemImage: "arrow.clockwise",
                handler: { }
            )
        )
    }
}
