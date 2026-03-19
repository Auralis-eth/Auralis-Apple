import SwiftUI

enum ShellStatusTone {
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

struct ShellStatusAction {
    let title: String
    let systemImage: String
    let handler: () -> Void
}

struct ShellStatusCard: View {
    let eyebrow: String?
    let title: String
    let message: String
    let systemImage: String
    let tone: ShellStatusTone
    let primaryAction: ShellStatusAction?
    let secondaryAction: ShellStatusAction?

    init(
        eyebrow: String? = nil,
        title: String,
        message: String,
        systemImage: String,
        tone: ShellStatusTone = .neutral,
        primaryAction: ShellStatusAction? = nil,
        secondaryAction: ShellStatusAction? = nil
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
                    Image(systemName: systemImage)
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
                            Button(action: secondaryAction.handler) {
                                Label(secondaryAction.title, systemImage: secondaryAction.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.surface.opacity(0.35), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

struct ShellStatusBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tone: ShellStatusTone
    let action: ShellStatusAction?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
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

struct ShellFirstRunStateView: View {
    var body: some View {
        ShellStatusCard(
            eyebrow: "First Run",
            title: "Start In Observe",
            message: "Paste a wallet, scan a QR code, or use a guest pass. Guest passes use public demo content so you can explore safely before saving anything on this device.",
            systemImage: "sparkles.rectangle.stack",
            tone: .neutral
        )
    }
}

struct ShellProviderFailureStateView: View {
    let error: Error?
    let isShowingCachedContent: Bool
    let retry: () -> Void

    var body: some View {
        ShellStatusCard(
            eyebrow: isShowingCachedContent ? "Degraded Mode" : "Provider Error",
            title: isShowingCachedContent ? "Refresh Paused" : "Collection Unavailable",
            message: message,
            systemImage: isShowingCachedContent ? "bolt.horizontal.circle" : "exclamationmark.triangle",
            tone: .warning,
            primaryAction: ShellStatusAction(
                title: "Try Again",
                systemImage: "arrow.clockwise",
                handler: retry
            )
        )
    }

    private var message: String {
        if isShowingCachedContent {
            return "Auralis could not refresh the provider just now. Your last synced collection is still visible so you can keep browsing safely."
        }

        return error?.localizedDescription ?? "Auralis could not reach the collection provider. Try again in a moment."
    }
}

enum ShellLibraryKind {
    case music
    case nft

    var title: String {
        switch self {
        case .music:
            return "No Music Yet"
        case .nft:
            return "No NFT Library Yet"
        }
    }

    var message: String {
        switch self {
        case .music:
            return "Your music NFT collection will appear here after a successful wallet sync."
        case .nft:
            return "NFTs from the active wallet will appear here after Auralis has something to index locally."
        }
    }

    var systemImage: String {
        switch self {
        case .music:
            return "music.note.list"
        case .nft:
            return "square.stack.3d.up"
        }
    }
}

struct ShellEmptyLibraryStateView: View {
    let kind: ShellLibraryKind

    var body: some View {
        ShellStatusCard(
            eyebrow: "Library",
            title: kind.title,
            message: kind.message,
            systemImage: kind.systemImage,
            tone: .neutral
        )
    }
}

struct ShellNoReceiptsStateView: View {
    var body: some View {
        ShellStatusCard(
            eyebrow: "Receipts",
            title: "No Receipts Recorded Yet",
            message: "Receipt history starts once Auralis records account and refresh events. Until then, there is nothing to inspect or export from this device.",
            systemImage: "doc.text.magnifyingglass",
            tone: .neutral
        )
    }
}

#Preview("Shell Statuses") {
    AuraScenicScreen(contentAlignment: .top) {
        VStack(spacing: 16) {
            ShellFirstRunStateView()
            ShellProviderFailureStateView(error: nil, isShowingCachedContent: true) { }
            ShellEmptyLibraryStateView(kind: .music)
            ShellNoReceiptsStateView()
        }
    }
}
