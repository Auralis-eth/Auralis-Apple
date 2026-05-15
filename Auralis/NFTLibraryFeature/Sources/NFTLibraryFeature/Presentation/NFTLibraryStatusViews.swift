import AuraUI
import NFTKit
import SwiftUI

public struct NFTLibraryEmptyStateView: View {
    public let title: String
    public let message: String
    public let isLoading: Bool
    public let refresh: @MainActor () async -> Void

    public init(
        title: String = "No NFTs Found",
        message: String = "We could not find NFTs for this wallet on the current chain yet. Try refreshing or switch to another saved account.",
        isLoading: Bool,
        refresh: @escaping @MainActor () async -> Void
    ) {
        self.title = title
        self.message = message
        self.isLoading = isLoading
        self.refresh = refresh
    }

    public var body: some View {
        AuraEmptyState(
            eyebrow: "Collection",
            title: title,
            message: message,
            systemImage: "photo.artframe",
            tone: .neutral,
            primaryAction: AuraFeedbackAction(
                title: "Refresh",
                systemImage: "arrow.clockwise",
                handler: refreshFromButton
            )
        )
        .disabled(isLoading)
        .accessibilityElement(children: .contain)
    }

    private func refreshFromButton() {
        Task {
            await refresh()
        }
    }
}

public struct NFTLibraryProviderFailureStateView: View {
    public let failure: NFTProviderFailurePresentation
    public let retry: @MainActor () async -> Void

    public init(failure: NFTProviderFailurePresentation, retry: @escaping @MainActor () async -> Void) {
        self.failure = failure
        self.retry = retry
    }

    public var body: some View {
        AuraEmptyState(
            eyebrow: "Provider",
            title: failure.title,
            message: failure.message,
            systemImage: failure.systemImage,
            tone: .warning,
            primaryAction: failure.isRetryable ? AuraFeedbackAction(
                title: "Retry",
                systemImage: "arrow.clockwise",
                handler: retryFromButton
            ) : nil
        )
        .accessibilityElement(children: .contain)
    }

    private func retryFromButton() {
        Task {
            await retry()
        }
    }
}

public struct NFTLibraryFailureBanner: View {
    public let failure: NFTProviderFailurePresentation
    public let retry: @MainActor () async -> Void

    public init(failure: NFTProviderFailurePresentation, retry: @escaping @MainActor () async -> Void) {
        self.failure = failure
        self.retry = retry
    }

    public var body: some View {
        AuraErrorBanner(
            title: failure.title,
            message: failure.message,
            systemImage: failure.systemImage,
            tone: .warning,
            action: failure.isRetryable ? AuraFeedbackAction(
                title: "Retry",
                systemImage: "arrow.clockwise",
                handler: retryFromButton
            ) : nil
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func retryFromButton() {
        Task {
            await retry()
        }
    }
}
