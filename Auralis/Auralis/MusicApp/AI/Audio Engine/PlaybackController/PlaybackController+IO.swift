import Foundation
import AVFoundation

@MainActor
extension PlaybackController {
    func maybePreloadNext() {
        guard let next = queue.peekNext(), let url = next.musicURL else { return }
        let task: Task<Void, Never> = Task { _ = try? await preloader.preload(nft: next, url: url) }
        preloadTasks.append(task)
    }

    func openFile(for nft: NFT) async throws -> AVAudioFile {
        guard let url = nft.musicURL else { throw URLError(.badURL) }
        return try await openURL(url)
    }

    func openURL(_ url: URL) async throws -> AVAudioFile {
        let local: URL
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            // Perform cache lookup off the main actor
            let resolved = try await AudioFileCache.shared.localURL(forRemote: url)
            local = resolved
        } else {
            local = url
        }
        return try AVAudioFile(forReading: local)
    }

    // Map underlying errors to PlaybackError categories for accurate UX
    func categorizePlaybackError(_ error: Error) -> PlaybackError {
        // Prefer network categorization for URL-related failures
        if let urlErr = error as? URLError { return .networkUnavailable }
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain { return .networkUnavailable }
        // AVAudioFile and file IO typically surface as Cocoa/OSStatus errors; treat as unreadable
        // Fallback to unknown if nothing matches
        return .fileUnreadable
    }
}
