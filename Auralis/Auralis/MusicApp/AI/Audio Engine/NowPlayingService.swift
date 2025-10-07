import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO

public protocol NowPlayingTelemetry {
    func artworkFetchAttempt(url: URL)
    func artworkFetchFailed(reason: String)
    func artworkBytesReceived(_ bytes: Int)
    func artworkDecodeDuration(_ seconds: TimeInterval)
    func progressForcedUpdate()
    func progressThrottledSkip()
}

public struct NoopNowPlayingTelemetry: NowPlayingTelemetry {
    public init() {}
    public func artworkFetchAttempt(url: URL) {}
    public func artworkFetchFailed(reason: String) {}
    public func artworkBytesReceived(_ bytes: Int) {}
    public func artworkDecodeDuration(_ seconds: TimeInterval) {}
    public func progressForcedUpdate() {}
    public func progressThrottledSkip() {}
}

@MainActor
public final class NowPlayingService {
    private var center: NowPlayingCentering
    private var info: [String: Any] = [:]
    private var lastProgressUptime: TimeInterval?
    private let cadence: TimeInterval
    private var artworkGeneration: Int = 0
    private var artworkTask: Task<Void, Never>?
    private let telemetry: NowPlayingTelemetry

    private var lastPublishedElapsed: TimeInterval?
    private var lastPublishedRate: Double?
    private let progressSignificantDelta: TimeInterval = 3.0

    private let artworkRequestTimeout: TimeInterval = 10
    private let artworkMaxBytes: Int = 10 * 1024 * 1024 // 10 MB cap
    private let allowedImageMIMETypes: Set<String> = ["image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic", "image/heif"]
    private let artworkMasterMaxPixelSize: CGFloat = 1024

    // Apply a coherent Now Playing bundle in a single assignment to avoid partial state
    private func applyNowPlaying(_ build: (inout [String: Any]) -> Void) {
        var snapshot = info
        build(&snapshot)
        info = snapshot
        center.nowPlayingInfo = snapshot
    }

    public init(center: NowPlayingCentering = DefaultNowPlayingCenter(), cadence: TimeInterval = 5.0, telemetry: NowPlayingTelemetry = NoopNowPlayingTelemetry()) {
        self.center = center
        self.cadence = cadence
        self.telemetry = telemetry
    }

    public func updateProgress(elapsed: TimeInterval, rate: Double, duration: TimeInterval) {
        let nowUptime = ProcessInfo.processInfo.systemUptime

        // Clamp elapsed based on duration semantics
        let clampedElapsed: TimeInterval = {
            if duration > 0 {
                return min(max(0, elapsed), duration)
            } else {
                return max(0, elapsed)
            }
        }()

        // Determine if we should bypass cadence due to a significant event
        let rateChanged: Bool = {
            if let last = lastPublishedRate { return abs(last - rate) > 0.0001 }
            return true
        }()
        let elapsedJumpedSignificantly: Bool = {
            if let last = lastPublishedElapsed { return abs(clampedElapsed - last) >= progressSignificantDelta }
            return true
        }()
        let shouldBypassCadence = rateChanged || elapsedJumpedSignificantly

        if !shouldBypassCadence {
            if let last = lastProgressUptime, nowUptime - last < cadence {
                // skip update to throttle progress updates (monotonic clock)
                telemetry.progressThrottledSkip()
                return
            }
        } else {
            // Bypass cadence due to seek or rate change
            telemetry.progressForcedUpdate()
        }

        // Publish progress update now as a coherent bundle
        lastProgressUptime = nowUptime
        applyNowPlaying {
            $0[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
            $0[MPNowPlayingInfoPropertyPlaybackRate] = rate
        }

        // Update trackers used for bypass logic
        lastPublishedElapsed = clampedElapsed
        lastPublishedRate = rate
    }

    public func setMetadata(title: String?, artist: String?, duration: TimeInterval, elapsed: TimeInterval, rate: Double) {
        let safeDuration = max(0, duration)
        let clampedElapsed: TimeInterval = {
            if safeDuration > 0 {
                return min(max(0, elapsed), safeDuration)
            } else {
                return max(0, elapsed)
            }
        }()
        applyNowPlaying {
            $0[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
            $0[MPNowPlayingInfoPropertyIsLiveStream] = safeDuration <= 0
            $0[MPMediaItemPropertyTitle] = title
            $0[MPMediaItemPropertyArtist] = artist
            $0[MPMediaItemPropertyPlaybackDuration] = safeDuration
            $0[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
            $0[MPNowPlayingInfoPropertyPlaybackRate] = rate
        }
        
        // Keep progress/rate trackers in sync when metadata is set
        lastPublishedElapsed = clampedElapsed
        lastPublishedRate = rate
        lastProgressUptime = ProcessInfo.processInfo.systemUptime
    }

    public func setArtwork(from urlString: String?) {
        // Cancel any in-flight artwork fetch/decode
        artworkTask?.cancel()
        artworkTask = nil

        guard let s = urlString, let url = URL(string: s) else { return }
        // Enforce HTTPS only
        guard url.scheme?.lowercased() == "https" else { return }

        telemetry.artworkFetchAttempt(url: url)

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
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    telemetry.artworkFetchFailed(reason: "http-status")
                    return
                }
                // Validate MIME type early
                guard let contentTypeHeader = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
                    telemetry.artworkFetchFailed(reason: "missing-content-type")
                    return
                }
                let mimeType = contentTypeHeader.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentTypeHeader
                guard allowedImageMIMETypes.contains(mimeType) else {
                    telemetry.artworkFetchFailed(reason: "mime-type")
                    return
                }
                // Enforce Content-Length if provided
                if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int(lenStr), len > artworkMaxBytes {
                    telemetry.artworkFetchFailed(reason: "content-length")
                    return
                }
                // Stream with hard cap
                for try await chunk in bytes {
                    if Task.isCancelled { return }
                    data.append(chunk)
                    if data.count > artworkMaxBytes {
                        telemetry.artworkFetchFailed(reason: "stream-cap-exceeded")
                        return
                    }
                }
            } catch {
                if Task.isCancelled { return }
                telemetry.artworkFetchFailed(reason: "network-error")
                return
            }
            if Task.isCancelled { return }

            telemetry.artworkBytesReceived(data.count)

            // Decode once into a bounded master image and discard raw bytes to reduce peak memory
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return }
            let screenScale = UIScreen.main.scale
            let decodeStart = ProcessInfo.processInfo.systemUptime
            let masterOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: artworkMasterMaxPixelSize * screenScale
            ]
            guard let masterCG = CGImageSourceCreateThumbnailAtIndex(src, 0, masterOpts as CFDictionary) else { return }
            let masterImage = UIImage(cgImage: masterCG, scale: screenScale, orientation: .up)
            let decodeDuration = ProcessInfo.processInfo.systemUptime - decodeStart
            telemetry.artworkDecodeDuration(decodeDuration)

            // Release raw data to avoid retaining large buffers in the provider closure
            data.removeAll(keepingCapacity: false)

            let boundsSize = masterImage.size
            // Small bounded cache by size bucket (in points): 256 / 512 / 1024
            var thumbnailCache: [Int: UIImage] = [:]
            let cacheLock = NSLock()
            func bucket(for size: CGSize) -> Int {
                let maxDim = max(size.width, size.height)
                if maxDim <= 256 { return 256 }
                else if maxDim <= 512 { return 512 }
                else { return 1024 }
            }

            let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { requested in
                // If requested matches the master size, return it directly
                if requested.equalTo(boundsSize) {
                    return masterImage
                }

                let b = bucket(for: requested)
                // Fast path: return cached bucket if available
                cacheLock.lock()
                if let cached = thumbnailCache[b] {
                    cacheLock.unlock()
                    return cached
                }
                cacheLock.unlock()

                // Compute a target size that preserves aspect ratio and does not exceed master
                let masterMax = max(boundsSize.width, boundsSize.height)
                let scale = min(CGFloat(b) / masterMax, 1.0)
                let targetSize = CGSize(width: boundsSize.width * scale, height: boundsSize.height * scale)

                let format = UIGraphicsImageRendererFormat()
                format.scale = UIScreen.main.scale
                format.opaque = false
                let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
                let rendered = renderer.image { _ in
                    masterImage.draw(in: CGRect(origin: .zero, size: targetSize))
                }

                // Store in cache under bucket key
                cacheLock.lock()
                thumbnailCache[b] = rendered
                cacheLock.unlock()
                return rendered
            }

            await MainActor.run {
                guard token == self.artworkGeneration else { return }
                if Task.isCancelled { return }
                self.applyNowPlaying {
                    $0[MPMediaItemPropertyArtwork] = artwork
                }
            }
        }
    }

    deinit {
        artworkTask?.cancel()
    }
}

