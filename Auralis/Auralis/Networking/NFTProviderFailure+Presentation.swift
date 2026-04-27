import Foundation

extension NFTProviderFailure {
    func presentation(
        mode: NFTProviderFailurePresentationMode
    ) -> NFTProviderFailurePresentation {
        switch mode {
        case .blocking:
            return NFTProviderFailurePresentation(
                mode: mode,
                title: blockingTitle,
                message: blockingMessage,
                systemImage: blockingSystemImage,
                isRetryable: isRetryable
            )
        case .degraded:
            return NFTProviderFailurePresentation(
                mode: mode,
                title: degradedTitle,
                message: degradedMessage,
                systemImage: "bolt.horizontal.circle",
                isRetryable: isRetryable
            )
        }
    }

    private var blockingTitle: String {
        switch kind {
        case .offline, .unavailable:
            return "Collection Unavailable"
        case .rateLimited:
            return "Refresh Delayed"
        case .invalidResponse:
            return "Provider Data Unavailable"
        case .invalidScope:
            return "Wallet Unavailable"
        case .misconfigured:
            return "Provider Unavailable"
        case .busy:
            return "Refresh In Progress"
        }
    }

    private var blockingMessage: String {
        switch kind {
        case .offline:
            return "Auralis could not reach the collection provider. Check your connection and try again."
        case .rateLimited:
            return "The collection provider is rate-limiting refreshes right now. Wait a moment and try again."
        case .invalidResponse:
            return "The collection provider returned data Auralis could not read. Try again later."
        case .invalidScope, .misconfigured, .busy:
            return message
        case .unavailable:
            return "Auralis could not reach the collection provider just now. Try again in a moment."
        }
    }

    private var blockingSystemImage: String {
        switch kind {
        case .offline:
            return "wifi.slash"
        case .rateLimited:
            return "hourglass"
        case .invalidResponse:
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .invalidScope, .misconfigured, .busy, .unavailable:
            return "exclamationmark.triangle"
        }
    }

    private var degradedTitle: String {
        switch kind {
        case .rateLimited:
            return "Showing Last Sync"
        default:
            return "Refresh Paused"
        }
    }

    private var degradedMessage: String {
        switch kind {
        case .offline:
            return "Auralis is offline right now. Your last synced collection is still visible so you can keep browsing safely."
        case .rateLimited:
            return "The provider is rate-limiting refreshes right now. Your last synced collection is still available while Auralis backs off."
        case .invalidResponse:
            return "The provider returned data Auralis could not read, so Auralis kept your last synced collection on screen."
        case .invalidScope:
            return "The current wallet scope is invalid, so Auralis kept your last synced collection on screen."
        case .misconfigured:
            return "This build cannot refresh the provider right now, so Auralis kept your last synced collection on screen."
        case .busy:
            return "A refresh is already running. Your last synced collection stays visible until it finishes."
        case .unavailable:
            return "Auralis could not refresh the provider just now. Your last synced collection is still visible so you can keep browsing safely."
        }
    }
}
