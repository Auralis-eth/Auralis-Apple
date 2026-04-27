import SwiftUI

struct AuraErrorBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tone: AuraFeedbackTone
    let action: AuraFeedbackAction?

    init(
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

    var body: some View {
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

#Preview {
    AuraScenicScreen(contentAlignment: .top) {
        AuraErrorBanner(
            title: "Showing Last Sync",
            message: "Auralis could not refresh right now, so cached content remains visible.",
            systemImage: "exclamationmark.triangle",
            action: AuraFeedbackAction(
                title: "Retry",
                systemImage: "arrow.clockwise",
                handler: { }
            )
        )
        .padding(.horizontal, 12)
    }
}
