import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO

@MainActor
public final class NowPlayingService {
    private var center: NowPlayingCentering
    private var info: [String: Any] = [:]
    private var lastProgressUpdate: Date?
    private let cadence: TimeInterval

    public init(center: NowPlayingCentering = DefaultNowPlayingCenter(), cadence: TimeInterval = 5.0) {
        self.center = center
        self.cadence = cadence
    }

    public func updateProgress(elapsed: TimeInterval, rate: Double, duration: TimeInterval) {
        let now = Date()
        if let last = lastProgressUpdate, now.timeIntervalSince(last) < cadence {
            // skip update to throttle progress updates
            return
        }
        lastProgressUpdate = now
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        center.nowPlayingInfo = info
    }

    public func setMetadata(title: String?, artist: String?, duration: TimeInterval, elapsed: TimeInterval, rate: Double) {
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = duration <= 0
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        info[MPMediaItemPropertyPlaybackDuration] = max(0, duration)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        center.nowPlayingInfo = info
    }

    public func setArtwork(from urlString: String?) {
        guard let s = urlString, let url = URL(string: s) else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            var data: Data?
            do {
                let (d, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) { data = d }
            } catch { data = nil }
            guard let data else { return }
            var artwork: MPMediaItemArtwork?
            let maxSize: CGSize = {
                if let src = CGImageSourceCreateWithData(data as CFData, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                   let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
                   let h = props[kCGImagePropertyPixelHeight] as? CGFloat { return CGSize(width: w, height: h) }
                return CGSize(width: 1024, height: 1024)
            }()
            artwork = MPMediaItemArtwork(boundsSize: maxSize) { requested in
                let scale = UIScreen.main.scale
                let pixelMax = max(requested.width, requested.height) * scale
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCache: false,
                    kCGImageSourceShouldCacheImmediately: false,
                    kCGImageSourceThumbnailMaxPixelSize: pixelMax
                ]
                guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return UIImage() }
                return UIImage(cgImage: cg, scale: scale, orientation: .up)
            }
            await MainActor.run {
                self.info[MPMediaItemPropertyArtwork] = artwork
                self.center.nowPlayingInfo = self.info
            }
        }
    }
}
