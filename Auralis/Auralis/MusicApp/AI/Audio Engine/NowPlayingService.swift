import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO

@MainActor
public final class NowPlayingService {
    private var center: NowPlayingCentering
    private var info: [String: Any] = [:]
    private var lastProgressUptime: TimeInterval?
    private let cadence: TimeInterval
    private var artworkGeneration: Int = 0
    private var artworkTask: Task<Void, Never>?

    private let artworkRequestTimeout: TimeInterval = 10
    private let artworkMaxBytes: Int = 10 * 1024 * 1024 // 10 MB cap
    private let allowedImageMIMETypes: Set<String> = ["image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic", "image/heif"]

    public init(center: NowPlayingCentering = DefaultNowPlayingCenter(), cadence: TimeInterval = 5.0) {
        self.center = center
        self.cadence = cadence
    }

    public func updateProgress(elapsed: TimeInterval, rate: Double, duration: TimeInterval) {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        if let last = lastProgressUptime, nowUptime - last < cadence {
            // skip update to throttle progress updates (monotonic clock)
            return
        }
        lastProgressUptime = nowUptime
        let clampedElapsed: TimeInterval = {
            if duration > 0 {
                return min(max(0, elapsed), duration)
            } else {
                return max(0, elapsed)
            }
        }()
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        center.nowPlayingInfo = info
    }

    public func setMetadata(title: String?, artist: String?, duration: TimeInterval, elapsed: TimeInterval, rate: Double) {
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = duration <= 0
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = artist
        let safeDuration = max(0, duration)
        let clampedElapsed: TimeInterval = {
            if safeDuration > 0 {
                return min(max(0, elapsed), safeDuration)
            } else {
                return max(0, elapsed)
            }
        }()
        info[MPMediaItemPropertyPlaybackDuration] = safeDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        center.nowPlayingInfo = info
    }

    public func setArtwork(from urlString: String?) {
        // Cancel any in-flight artwork fetch/decode
        artworkTask?.cancel()
        artworkTask = nil

        guard let s = urlString, let url = URL(string: s) else { return }
        // Enforce HTTPS only
        guard url.scheme?.lowercased() == "https" else { return }

        artworkGeneration += 1
        let token = artworkGeneration

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: artworkRequestTimeout)
        request.httpMethod = "GET"

        artworkTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            var data = Data()
            do {
                let (bytes, resp) = try await URLSession.shared.bytes(for: request)
                if Task.isCancelled { return }
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
                // Validate MIME type early
                guard let contentTypeHeader = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() else { return }
                let mimeType = contentTypeHeader.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentTypeHeader
                guard allowedImageMIMETypes.contains(mimeType) else { return }
                // Enforce Content-Length if provided
                if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int(lenStr), len > artworkMaxBytes { return }
                // Stream with hard cap
                for try await chunk in bytes {
                    if Task.isCancelled { return }
                    data.append(chunk)
                    if data.count > artworkMaxBytes { return }
                }
            } catch {
                if Task.isCancelled { return }
                return
            }
            if Task.isCancelled { return }

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
                guard token == self.artworkGeneration else { return }
                if Task.isCancelled { return }
                self.info[MPMediaItemPropertyArtwork] = artwork
                self.center.nowPlayingInfo = self.info
            }
        }
    }

    deinit {
        artworkTask?.cancel()
    }
}

