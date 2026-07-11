import Foundation

public enum MediaOfflineState: String, Codable, Equatable, Sendable {
    case queued
    case downloading
    case available
    case failed
    case cancelled
}

