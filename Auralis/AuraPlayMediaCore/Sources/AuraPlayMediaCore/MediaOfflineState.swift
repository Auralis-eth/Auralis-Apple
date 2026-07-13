import Foundation

/// The lifecycle of an explicit offline download request
/// (queued → downloading → available/failed/cancelled). Complements
/// ``AuraCachedFileState``, which describes what the cache currently holds on
/// disk for a media item regardless of how it got there.
public enum MediaOfflineState: String, Codable, Equatable, Sendable {
    case queued
    case downloading
    case available
    case failed
    case cancelled
}

