import Foundation

public enum AuraPlayError: Error, Equatable, Sendable {
    case mediaUnavailableOffline
    case engineStartFailed
    case unsupportedFormat(String?)
    case corruptedFile(URL)
    case downloadFailed(String)
    case cacheIndexCorrupted
    case invalidMediaURL(URL)
}
