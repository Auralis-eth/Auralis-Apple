import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO

public enum ArtworkFailureReason: String {
    case http_status
    case http_5xx_retry
    case mime_unsupported
    case missing_content_type
    case content_length
    case stream_cap_exceeded
    case network_error
    case cache_miss_304
    case decode_fail
    case redirect_rejected
}

public protocol NowPlayingTelemetry {
    func artworkFetchAttempt(url: URL)
    func artworkFetchFailed(_ reason: ArtworkFailureReason)
    func artworkBytesReceived(_ bytes: Int)
    func artworkDecodeDuration(_ seconds: TimeInterval)
    func progressForcedUpdate()
    func progressThrottledSkip()
    func artworkCacheHit()
    func artworkCacheMiss()
    func artworkMimeSeen(_ mime: String)
    func artworkRedirectApplied(count: Int, finalHost: String)
}

public struct NoopNowPlayingTelemetry: NowPlayingTelemetry {
    public init() {}
    public func artworkFetchAttempt(url: URL) {}
    public func artworkFetchFailed(_ reason: ArtworkFailureReason) {}
    public func artworkBytesReceived(_ bytes: Int) {}
    public func artworkDecodeDuration(_ seconds: TimeInterval) {}
    public func progressForcedUpdate() {}
    public func progressThrottledSkip() {}
    public func artworkCacheHit() {}
    public func artworkCacheMiss() {}
    public func artworkMimeSeen(_ mime: String) {}
    public func artworkRedirectApplied(count: Int, finalHost: String) {}
}

@MainActor
public final class NowPlayingService {
    private var center: NowPlayingCentering
    private var info: [String: Any] = [:]
    private var lastProgressUptime: TimeInterval?
    private let cadence: TimeInterval
    /// Minimum elapsed-time jump that bypasses progress throttling.
    /// Tuned to 1.0s so micro-seeks (~1–2s) reflect immediately on system surfaces
    /// while continuous playback still uses cadence for battery efficiency.
    private let progressSignificantDelta: TimeInterval = 1.0
    private var artworkGeneration: Int = 0
    private var artworkTask: Task<Void, Never>?
    private let telemetry: NowPlayingTelemetry

    private var failureCounts: [ArtworkFailureReason: Int] = [:]

    // Sample and forward failure reasons to telemetry to avoid dashboard spam under fault storms.
    // First 10 events per reason are forwarded, then every 10th thereafter.
    private func sampleAndLogFailure(_ reason: ArtworkFailureReason) {
        let next = (failureCounts[reason] ?? 0) + 1
        failureCounts[reason] = next
        if next <= 10 || next % 10 == 0 {
            telemetry.artworkFetchFailed(reason)
        }
    }

    private var lastPublishedElapsed: TimeInterval?
    private var lastPublishedRate: Double?

    private let artworkRequestTimeout: TimeInterval = 5
    private let artworkMaxBytes: Int = 10 * 1024 * 1024 // 10 MB cap
    private let allowedImageMIMETypes: Set<String> = ["image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic", "image/heif"]
    private var artworkMasterMaxPixelSize: CGFloat = 1024
    private let allowedRedirectHosts: Set<String>?

    // Apply a coherent Now Playing bundle in a single assignment to avoid partial state
    private func applyNowPlaying(_ build: (inout [String: Any]) -> Void) {
        var snapshot = info
        build(&snapshot)
        info = snapshot
        center.nowPlayingInfo = snapshot
    }

    public init(center: NowPlayingCentering = DefaultNowPlayingCenter(), cadence: TimeInterval = 5.0, telemetry: NowPlayingTelemetry = NoopNowPlayingTelemetry(), decodeMaxPixelSize: CGFloat? = nil, allowedRedirectHosts: Set<String>? = nil) {
        self.center = center
        self.cadence = cadence
        self.telemetry = telemetry
        self.allowedRedirectHosts = allowedRedirectHosts
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

        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: artworkRequestTimeout)
        request.httpMethod = "GET"

        // Capture UI-related values on the main actor for use off-main
        let screenScale = UIScreen.main.scale
        let decodeCap = self.artworkMasterMaxPixelSize
        let allowedMimes = self.allowedImageMIMETypes
        let maxBytes = self.artworkMaxBytes
        let telemetry = self.telemetry
        let originalHost = url.host?.lowercased()
        let redirectAllowlist = self.allowedRedirectHosts?.map { $0.lowercased() }

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
                        await MainActor.run { self.sampleAndLogFailure(.http_status) }
                        return
                    }
                    // Enforce redirect/host policy: final URL must be https and same-host or allowlisted
                    let finalURL = http.url
                    let finalSchemeOK = finalURL?.scheme?.lowercased() == "https"
                    let finalHost = finalURL?.host?.lowercased()
                    let sameHost = (finalHost != nil && finalHost == originalHost)
                    let inAllowlist = (finalHost != nil && (redirectAllowlist?.contains(finalHost!) ?? false))
                    if !(finalSchemeOK && (sameHost || inAllowlist)) {
                        await MainActor.run { self.sampleAndLogFailure(.redirect_rejected) }
                        return
                    }
                    // Best-effort redirect count estimation (0 if same host, 1 if different)
                    let redirectCount = (sameHost ? 0 : 1)

                    // Handle 304 Not Modified by loading cached response data
                    if http.statusCode == 304 {
                        if let cached = URLCache.shared.cachedResponse(for: request),
                           let cachedHTTP = cached.response as? HTTPURLResponse {
                            // Validate cached MIME type
                            if let ct = cachedHTTP.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                                let cachedMime = ct.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ct
                                telemetry.artworkMimeSeen(cachedMime)
                                guard allowedMimes.contains(cachedMime) else {
                                    await MainActor.run { self.sampleAndLogFailure(.mime_unsupported) }
                                    return
                                }
                            }
                            data = cached.data
                            telemetry.artworkCacheHit()
                            telemetry.artworkRedirectApplied(count: redirectCount, finalHost: finalHost ?? "")
                            fetchSucceeded = true
                            break attemptLoop
                        } else {
                            await MainActor.run { self.sampleAndLogFailure(.cache_miss_304) }
                            return
                        }
                    }
                    // Non-success status handling with transient retry for 5xx only
                    guard (200...299).contains(http.statusCode) else {
                        if (500...599).contains(http.statusCode), attempt == 0 {
                            await MainActor.run { self.sampleAndLogFailure(.http_5xx_retry) }
                            await shortBackoff()
                            continue attemptLoop
                        } else {
                            await MainActor.run { self.sampleAndLogFailure(.http_status) }
                            return
                        }
                    }
                    // Validate MIME type early
                    guard let contentTypeHeader = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
                        await MainActor.run { self.sampleAndLogFailure(.missing_content_type) }
                        return
                    }
                    let mimeType = contentTypeHeader.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentTypeHeader
                    telemetry.artworkMimeSeen(mimeType)
                    guard allowedMimes.contains(mimeType) else {
                        await MainActor.run { self.sampleAndLogFailure(.mime_unsupported) }
                        return
                    }
                    // Enforce Content-Length if provided
                    if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int(lenStr), len > maxBytes {
                        await MainActor.run { self.sampleAndLogFailure(.content_length) }
                        return
                    }
                    // Stream with hard cap
                    for try await chunk in bytes {
                        if Task.isCancelled { return }
                        data.append(chunk)
                        if data.count > maxBytes {
                            await MainActor.run { self.sampleAndLogFailure(.stream_cap_exceeded) }
                            return
                        }
                    }

                    telemetry.artworkRedirectApplied(count: redirectCount, finalHost: finalHost ?? "")
                    telemetry.artworkCacheMiss()

                    // If we made it here, fetch succeeded
                    fetchSucceeded = true
                    break attemptLoop
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run { self.sampleAndLogFailure(.network_error) }
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

            // Decode once into a bounded master CGImage using ImageIO (no UIKit off-main)
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
                await MainActor.run { self.sampleAndLogFailure(.decode_fail) }
                return
            }
            let decodeStart = ProcessInfo.processInfo.systemUptime
            let masterOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: decodeCap * screenScale
            ]
            guard let masterCG = CGImageSourceCreateThumbnailAtIndex(src, 0, masterOpts as CFDictionary) else {
                await MainActor.run { self.sampleAndLogFailure(.decode_fail) }
                return
            }
            let decodeDuration = ProcessInfo.processInfo.systemUptime - decodeStart
            telemetry.artworkDecodeDuration(decodeDuration)

            // Release raw data to avoid retaining large buffers
            data.removeAll(keepingCapacity: false)

            // Compute logical (points) size from pixel size
            let boundsSize = CGSize(width: CGFloat(masterCG.width) / screenScale, height: CGFloat(masterCG.height) / screenScale)

            // Helper to downscale a CGImage to a target pixel size using CoreGraphics (no UIKit)
            func cgImageScaled(_ image: CGImage, toPixelSize size: CGSize) -> CGImage? {
                guard size.width > 0, size.height > 0 else { return nil }
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bytesPerPixel = 4
                let bitsPerComponent = 8
                let bytesPerRow = Int(size.width) * bytesPerPixel
                guard let ctx = CGContext(data: nil,
                                          width: Int(size.width),
                                          height: Int(size.height),
                                          bitsPerComponent: bitsPerComponent,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(origin: .zero, size: size))
                return ctx.makeImage()
            }

            // Prepare bucketed CGImages off-main (256/512/1024 points), limited by master size
            let bucketPoints: [Int] = [256, 512, 1024]
            var cgBucketImages: [Int: CGImage] = [:]
            let masterMaxPixels = CGFloat(max(masterCG.width, masterCG.height))
            let masterMaxPoints = masterMaxPixels / screenScale
            for bp in bucketPoints {
                let bpPoints = CGFloat(bp)
                // Skip buckets larger than master
                if bpPoints > masterMaxPoints { continue }
                let scale = min(bpPoints / max(boundsSize.width, boundsSize.height), 1.0)
                let targetPixels = CGSize(width: boundsSize.width * scale * screenScale,
                                          height: boundsSize.height * scale * screenScale)
                if let scaled = cgImageScaled(masterCG, toPixelSize: targetPixels) {
                    cgBucketImages[bp] = scaled
                }
            }

            await MainActor.run {
                guard token == self.artworkGeneration else { return }
                if Task.isCancelled { return }

                // Wrap CGImages as UIImages on the main actor only
                let masterImage = UIImage(cgImage: masterCG, scale: screenScale, orientation: .up)

                // Build an immutable, bounded cache (<= 3 buckets) of pre-rendered UIImages on main
                let thumbnailCache: [Int: UIImage] = {
                    var tmp: [Int: UIImage] = [:]
                    for (k, v) in cgBucketImages {
                        tmp[k] = UIImage(cgImage: v, scale: screenScale, orientation: .up)
                    }
                    return tmp
                }()

                // Provider-closure invariants:
                // - No UIKit rendering or blocking I/O inside the closure.
                // - Only returns prebuilt UIImages (created on main above).
                // - Cache is immutable and bounded (<= 3 buckets: 256/512/1024).
                // - Safe to be called on any thread.

                #if DEBUG
                precondition(thumbnailCache.count <= 3, "Artwork cache should be bounded to <= 3 buckets")
                #endif

                let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { requested in
                    // Invariant checks (DEBUG only): do not add rendering or I/O here.
                    #if DEBUG
                    precondition(thumbnailCache.count <= 3, "Artwork cache should be bounded to <= 3 buckets")
                    #endif

                    // Return prebuilt images only; no resizing or UIKit off-main here
                    if requested.equalTo(boundsSize) {
                        return masterImage
                    }
                    let maxDim = max(requested.width, requested.height)
                    let b: Int
                    if maxDim <= 256 { b = 256 }
                    else if maxDim <= 512 { b = 512 }
                    else { b = 1024 }
                    return thumbnailCache[b] ?? masterImage
                }

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

