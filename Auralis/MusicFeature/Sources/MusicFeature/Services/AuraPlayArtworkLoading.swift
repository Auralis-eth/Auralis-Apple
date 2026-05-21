import Foundation

public protocol AuraPlayArtworkLoading: Sendable {
    func artworkURL(for track: AuraPlayTrack?) throws -> URL?
}

public struct AuraPlayTrackArtworkLoader: AuraPlayArtworkLoading, Sendable {
    public init() {}

    public func artworkURL(for track: AuraPlayTrack?) throws -> URL? {
        guard let track else {
            return nil
        }
        guard let imageURLString = track.imageURLString, !imageURLString.isEmpty else {
            return nil
        }
        guard let url = URL(string: imageURLString) else {
            throw AuraPlayError.artwork("AuraPlay received an invalid artwork URL for the active track.")
        }
        return url
    }
}
