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
        AuraEmptyState(
            eyebrow: eyebrow,
            title: title,
            message: message,
            systemImage: systemImage,
            tone: tone.feedbackTone,
            primaryAction: primaryAction?.feedbackAction,
            secondaryAction: secondaryAction?.feedbackAction
        )
    }
}

struct ShellStatusBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tone: ShellStatusTone
    let action: ShellStatusAction?

    var body: some View {
        AuraErrorBanner(
            title: title,
            message: message,
            systemImage: systemImage,
            tone: tone.feedbackTone,
            action: action?.feedbackAction
        )
    }
}

private extension ShellStatusTone {
    var feedbackTone: AuraFeedbackTone {
        switch self {
        case .neutral:
            return .neutral
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }
}

private extension ShellStatusAction {
    var feedbackAction: AuraFeedbackAction {
        AuraFeedbackAction(
            title: title,
            systemImage: systemImage,
            handler: handler
        )
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
    let failure: NFTProviderFailurePresentation
    let retry: () -> Void

    var body: some View {
        ShellStatusCard(
            eyebrow: failure.mode == .degraded ? "Degraded Mode" : "Provider Error",
            title: failure.title,
            message: failure.message,
            systemImage: failure.systemImage,
            tone: failure.mode == .degraded ? .warning : .critical,
            primaryAction: failure.isRetryable ? ShellStatusAction(
                title: "Try Again",
                systemImage: "arrow.clockwise",
                handler: retry
            ) : nil
        )
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
    let previewFailure = NFTProviderFailure(
        error: NFTFetcher.FetcherError.networkError(URLError(.notConnectedToInternet))
    )?.presentation(mode: .degraded)

    AuraScenicScreen(contentAlignment: .top) {
        VStack(spacing: 16) {
            ShellFirstRunStateView()
            if let previewFailure {
                ShellProviderFailureStateView(failure: previewFailure) { }
            }
            ShellEmptyLibraryStateView(kind: .music)
            ShellNoReceiptsStateView()
        }
    }
}
