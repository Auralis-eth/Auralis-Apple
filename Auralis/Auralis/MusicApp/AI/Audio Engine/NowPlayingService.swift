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

    private let artworkRequestTimeout: TimeInterval = 5
    private let artworkMaxBytes: Int = 10 * 1024 * 1024 // 10 MB cap
    private let allowedImageMIMETypes: Set<String> = ["image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic", "image/heif"]
    private var artworkMasterMaxPixelSize: CGFloat = 1024

    // Apply a coherent Now Playing bundle in a single assignment to avoid partial state
    private func applyNowPlaying(_ build: (inout [String: Any]) -> Void) {
        var snapshot = info
        build(&snapshot)
        info = snapshot
        center.nowPlayingInfo = snapshot
    }

    public init(center: NowPlayingCentering = DefaultNowPlayingCenter(), cadence: TimeInterval = 5.0, telemetry: NowPlayingTelemetry = NoopNowPlayingTelemetry(), decodeMaxPixelSize: CGFloat? = nil) {
        self.center = center
        self.cadence = cadence
        self.telemetry = telemetry
        if let decodeMaxPixelSize, decodeMaxPixelSize > 0 {
            self.artworkMasterMaxPixelSize = decodeMaxPixelSize
        }
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

    public func setMetadata(title: String?, artist: String?, album: String? = nil, duration: TimeInterval, elapsed: TimeInterval, rate: Double, defaultRate: Double? = nil) {
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
            let isLive = safeDuration <= 0
            $0[MPNowPlayingInfoPropertyIsLiveStream] = isLive
            $0[MPMediaItemPropertyTitle] = title
            $0[MPMediaItemPropertyArtist] = artist
            if let album { $0[MPMediaItemPropertyAlbumTitle] = album } else { $0.removeValue(forKey: MPMediaItemPropertyAlbumTitle) }
            // For live streams, ensure duration is 0 to discourage scrubbers
            $0[MPMediaItemPropertyPlaybackDuration] = isLive ? 0 : safeDuration
            $0[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
            $0[MPNowPlayingInfoPropertyPlaybackRate] = rate
            if let defaultRate { $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultRate } else { $0.removeValue(forKey: MPNowPlayingInfoPropertyDefaultPlaybackRate) }
        }
        
        // Keep progress/rate trackers in sync when metadata is set
        lastPublishedElapsed = clampedElapsed
        lastPublishedRate = rate
        lastProgressUptime = ProcessInfo.processInfo.systemUptime
    }

    // Backward-compatible overload preserving original API
    public func setMetadata(title: String?, artist: String?, duration: TimeInterval, elapsed: TimeInterval, rate: Double) {
        setMetadata(title: title, artist: artist, album: nil, duration: duration, elapsed: elapsed, rate: rate, defaultRate: nil)
    }

    /// Override the maximum decode target size (in points) for artwork thumbnails.
    /// Pass a value > 0 to allow larger (or smaller) decode caps than the default 1024.
    /// The actual pixel cap is this value multiplied by the current screen scale.
    public func setArtworkDecodeMaxPixelSize(_ size: CGFloat) {
        guard size > 0 else { return }
        artworkMasterMaxPixelSize = size
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

        // Capture main-actor properties for use off the main actor
        let decodeCap = self.artworkMasterMaxPixelSize
        let allowedMimes = self.allowedImageMIMETypes
        let maxBytes = self.artworkMaxBytes
        let telemetry = self.telemetry

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: artworkRequestTimeout)
        request.httpMethod = "GET"

        artworkTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            var data = Data()
            var fetchSucceeded = false

            // Helper to perform a short backoff between attempts
            func shortBackoff() async {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            }

            attemptLoop: for attempt in 0..<2 { // bounded: at most 1 retry
                if Task.isCancelled { return }
                data.removeAll(keepingCapacity: false)

                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: request)
                    if Task.isCancelled { return }
                    guard let http = resp as? HTTPURLResponse else {
                        telemetry.artworkFetchFailed(reason: "http-status")
                        return
                    }
                    // Non-success status handling with transient retry for 5xx only
                    guard (200...299).contains(http.statusCode) else {
                        if (500...599).contains(http.statusCode), attempt == 0 {
                            telemetry.artworkFetchFailed(reason: "http-5xx-retry")
                            await shortBackoff()
                            continue attemptLoop
                        } else {
                            telemetry.artworkFetchFailed(reason: "http-status")
                            return
                        }
                    }
                    // Validate MIME type early
                    guard let contentTypeHeader = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
                        telemetry.artworkFetchFailed(reason: "missing-content-type")
                        return
                    }
                    let mimeType = contentTypeHeader.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentTypeHeader
                    guard allowedMimes.contains(mimeType) else {
                        telemetry.artworkFetchFailed(reason: "mime-type")
                        return
                    }
                    // Enforce Content-Length if provided
                    if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int(lenStr), len > maxBytes {
                        telemetry.artworkFetchFailed(reason: "content-length")
                        return
                    }
                    // Stream with hard cap
                    for try await chunk in bytes {
                        if Task.isCancelled { return }
                        data.append(chunk)
                        if data.count > maxBytes {
                            telemetry.artworkFetchFailed(reason: "stream-cap-exceeded")
                            return
                        }
                    }

                    // If we made it here, fetch succeeded
                    fetchSucceeded = true
                    break attemptLoop
                } catch {
                    if Task.isCancelled { return }
                    telemetry.artworkFetchFailed(reason: "network-error")
                    // Retry once on transient network error
                    if attempt == 0 {
                        await shortBackoff()
                        continue attemptLoop
                    } else {
                        return
                    }
                }
            }

            guard fetchSucceeded else { return }
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
                kCGImageSourceThumbnailMaxPixelSize: decodeCap * screenScale
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

    /// Explicitly clear the currently published artwork.
    /// - Note: This cancels any in-flight artwork task and prevents stale applies by advancing the generation token.
    public func clearArtwork() {
        // Cancel any in-flight work and advance generation to invalidate pending results
        artworkTask?.cancel()
        artworkTask = nil
        artworkGeneration += 1

        // Remove artwork coherently without touching other metadata/progress keys
        applyNowPlaying {
            $0.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
    }

    deinit {
        artworkTask?.cancel()
    }
}

