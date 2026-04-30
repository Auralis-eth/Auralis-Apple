import Foundation

@MainActor
protocol AuraPlayArtworkLoading {
    func artworkURL(for track: AudioEngine.Track?) throws -> URL?
}

@MainActor
struct AuraPlayTrackArtworkLoader: AuraPlayArtworkLoading {
    func artworkURL(for track: AudioEngine.Track?) throws -> URL? {
        guard let track else {
            return nil
        }
        guard let imageURLString = track.imageUrl, !imageURLString.isEmpty else {
            return nil
        }
        guard let url = URL(string: imageURLString) else {
            throw AuraPlayError.artwork("AuraPlay received an invalid artwork URL for the active track.")
        }
        return url
    }
}
