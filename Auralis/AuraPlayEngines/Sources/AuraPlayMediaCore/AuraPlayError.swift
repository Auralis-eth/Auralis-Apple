import Foundation

/// Shared playback, caching, and download errors.
///
/// Equality is synthesized, so cases with associated values (notably
/// `downloadFailed`) compare their message text. Treat `==` as a test
/// convenience; match on the case, not the message, to classify failures.
public enum AuraPlayError: Error, Equatable, Sendable {
    case mediaUnavailableOffline
    case engineStartFailed
    case unsupportedFormat(String?)
    case corruptedFile(URL)
    case downloadFailed(String)
    case cacheIndexCorrupted
    case invalidMediaURL(URL)
}

extension AuraPlayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .mediaUnavailableOffline:
            return "This media isn't available offline."
        case .engineStartFailed:
            return "Playback couldn't be started."
        case .unsupportedFormat(let format):
            if let format {
                return "The media format “\(format)” isn't supported."
            }
            return "The media format isn't supported."
        case .corruptedFile(let url):
            return "The media file “\(url.lastPathComponent)” is corrupted."
        case .downloadFailed(let reason):
            return "The download failed: \(reason)"
        case .cacheIndexCorrupted:
            return "The media cache index is corrupted."
        case .invalidMediaURL(let url):
            return "The media URL isn't valid: \(url.absoluteString)"
        }
    }
}
