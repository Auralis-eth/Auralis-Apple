import Foundation

@MainActor
public protocol AuraPlayArtworkLoading {
    func artworkURL(for track: AuraPlayTrack?) throws -> URL?
}

@MainActor
public struct AuraPlayTrackArtworkLoader: AuraPlayArtworkLoading {
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
