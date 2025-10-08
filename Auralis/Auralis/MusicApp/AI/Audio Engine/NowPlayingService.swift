import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO
import Network

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
    case format_suppressed
}

public protocol NowPlayingTelemetry {
    /// Threading contract: Implementations must be thread-safe.
    /// Methods may be invoked from any thread (including off-main) and from async contexts.
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
    func networkPolicyApplied(onCellular: Bool, timeout: TimeInterval, attempt: Int)
    func artworkFetchDuration(_ seconds: TimeInterval)
    // NP-024: 304 fallback success indicator
    func artworkCache304FallbackSucceeded()
    // NP-027: Validator usage tracking
    func artworkValidatorsUsed()
    func artworkValidatorsMissing()
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
    public func networkPolicyApplied(onCellular: Bool, timeout: TimeInterval, attempt: Int) {}
    public func artworkFetchDuration(_ seconds: TimeInterval) {}
    public func artworkCache304FallbackSucceeded() {}
    public func artworkValidatorsUsed() {}
    public func artworkValidatorsMissing() {}
}

@MainActor
public final class NowPlayingService {
    private var center: NowPlayingCentering
    private var info: [String: Any] = [:]
    private var lastProgressUptime: TimeInterval?
    private let cadence: TimeInterval
    /// Micro-seek bypass threshold (in seconds).
    ///
    /// Rationale:
    /// - We throttle progress updates to the system using `cadence` to conserve battery and avoid noisy UI churn.
    /// - However, small user-initiated seeks (typically ±1–2 seconds) should reflect immediately on system surfaces
    ///   like Control Center and the Lock Screen so the scrubber jumps without delay.
    /// - Setting this to 1.0s means any elapsed-time change of ≥ 1.0s bypasses cadence and publishes immediately,
    ///   while continuous playback (small deltas) remains throttled by `cadence`.
    private let progressSignificantDelta: TimeInterval = 1.0
    private var artworkGeneration: Int = 0
    private var artworkTask: Task<Void, Never>?
    private let telemetry: NowPlayingTelemetry

    // NP-025: Configurable bucket strategy
    public enum ArtworkBucketStrategy { case one, two, three }
    private let bucketStrategy: ArtworkBucketStrategy
    
    // Memory purge control for provider closures; holds bucket cache to allow release under pressure
    private final class ArtworkCacheControl {
        final class ProviderMetrics {
            private let q = DispatchQueue(label: "NowPlayingService.ArtworkProviderMetrics", qos: .utility)
            private var le256: Int = 0
            private var le512: Int = 0
            private var gt512: Int = 0
            func record(requestedMaxDimension: CGFloat) {
                q.async { [requestedMaxDimension] in
                    if requestedMaxDimension <= 256 { self.le256 += 1 }
                    else if requestedMaxDimension <= 512 { self.le512 += 1 }
                    else { self.gt512 += 1 }
                }
            }
            func snapshot() -> (le256: Int, le512: Int, gt512: Int) {
                return q.sync { (le256, le512, gt512) }
            }
        }
        var purge = false
        var buckets: [Int: UIImage]? = nil
        let metrics = ProviderMetrics()
    }
    private var currentArtworkControl: ArtworkCacheControl?

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

    private let runtimeSupportedMIMEs: Set<String>
    private var suppressedMIMEs: Set<String> = []
    private var mimeDecodeFailureCounts: [String: Int] = [:]
    private let decodeSuppressionThreshold: Int = 3

    private let pathMonitor = NWPathMonitor()
    private var isCellular: Bool = false
    private let cellularFastTimeout: TimeInterval = 2.0

    // NP-023 and NP-027: MetricsCollector for URLSessionTaskDelegate and validator analysis
    private final class MetricsCollector: NSObject, URLSessionTaskDelegate {
        private(set) var metrics: URLSessionTaskMetrics?
        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            self.metrics = metrics
        }
    }

    nonisolated private func analyzeMetrics(_ metrics: URLSessionTaskMetrics) -> (redirects: Int, finalHost: String?, validatorsUsed: Bool) {
        var redirects = 0
        var finalHost: String? = nil
        var validatorsUsed = false
        for t in metrics.transactionMetrics {
            if let resp = t.response as? HTTPURLResponse, (300...399).contains(resp.statusCode) {
                redirects += 1
            }
            if let host = t.request.url?.host { finalHost = host }
            let headers = (t.request as URLRequest).allHTTPHeaderFields ?? [:]
            if headers.keys.contains(where: { $0.caseInsensitiveCompare("If-None-Match") == .orderedSame }) ||
               headers.keys.contains(where: { $0.caseInsensitiveCompare("If-Modified-Since") == .orderedSame }) {
                validatorsUsed = true
            }
        }
        return (redirects, finalHost, validatorsUsed)
    }

    // Apply a coherent Now Playing bundle in a single assignment to avoid partial state
    private func applyNowPlaying(_ build: (inout [String: Any]) -> Void) {
        var snapshot = info
        build(&snapshot)
        info = snapshot
        center.nowPlayingInfo = snapshot
    }

    private func handleMemoryPressure() {
        // Signal current artwork provider to purge bucket images; keep master only
        currentArtworkControl?.purge = true
        currentArtworkControl?.buckets = nil
    }

    private static func detectRuntimeSupportedMIMEs() -> Set<String> {
        var supported: Set<String> = ["image/jpeg", "image/jpg", "image/png"]
        if let utis = CGImageSourceCopyTypeIdentifiers() as? [String] {
            let set = Set(utis)
            if set.contains("org.webmproject.webp") { supported.insert("image/webp") }
            if set.contains("public.heic") { supported.insert("image/heic") }
            if set.contains("public.heif") { supported.insert("image/heif") }
        }
        return supported
    }

    // Derive a stable placeholder color from a URL string (hue hashing)
    private func placeholderColor(for url: URL) -> UIColor {
        let s = url.absoluteString.unicodeScalars.reduce(UInt64(0)) { ($0 &* 1099511628211) ^ UInt64($1.value) }
        let hue = CGFloat((s % 360)) / 360.0
        return UIColor(hue: hue, saturation: 0.2, brightness: 0.9, alpha: 1.0)
    }

    // Build a very lightweight placeholder artwork using a solid color image
    private func buildPlaceholderArtwork(for url: URL, scale: CGFloat) -> MPMediaItemArtwork {
        // Keep the logical bounds at a typical square; image itself is tiny to minimize memory
        let boundsSize = CGSize(width: 512, height: 512)
        let color = placeholderColor(for: url)
        let pixelSize = CGSize(width: 32 * scale, height: 32 * scale)

        // Create a tiny solid-color image on main
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale), format: format)
        let img = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))
        }

        // Return a simple provider that always returns this small image (safe and cheap)
        let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            return img
        }
        return artwork
    }

    public init(center: NowPlayingCentering = DefaultNowPlayingCenter(),
                cadence: TimeInterval = 5.0,
                telemetry: NowPlayingTelemetry = NoopNowPlayingTelemetry(),
                decodeMaxPixelSize: CGFloat? = nil,
                allowedRedirectHosts: Set<String>? = nil,
                bucketStrategy: ArtworkBucketStrategy = .two) {
        self.center = center
        self.cadence = cadence
        self.telemetry = telemetry
        self.allowedRedirectHosts = allowedRedirectHosts
        self.bucketStrategy = bucketStrategy
        if let decodeMaxPixelSize, decodeMaxPixelSize > 0 {
            self.artworkMasterMaxPixelSize = decodeMaxPixelSize
        }
        self.runtimeSupportedMIMEs = NowPlayingService.detectRuntimeSupportedMIMEs()

        // Start network path monitoring for adaptive timeouts
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let onCell = path.usesInterfaceType(.cellular)
            Task { [weak self] in
                await MainActor.run {
                    self?.isCellular = onCell
                }
            }
        }
        let q = DispatchQueue(label: "NowPlayingService.Network")
        pathMonitor.start(queue: q)

        #if DEBUG
        // NP-022: Lightweight probe to ensure telemetry can be invoked off-main without assumptions.
        Task.detached(priority: .background) { [telemetry] in
            telemetry.progressThrottledSkip()
        }
        #endif

        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleMemoryPressure()
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

        // If there is no current artwork, publish a lightweight placeholder immediately
        if info[MPMediaItemPropertyArtwork] == nil {
            let placeholder = buildPlaceholderArtwork(for: url, scale: UIScreen.main.scale)
            applyNowPlaying {
                $0[MPMediaItemPropertyArtwork] = placeholder
            }
        }

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
        let runtimeSupportedMimes = self.runtimeSupportedMIMEs
        let decodeThreshold = self.decodeSuppressionThreshold
        let onCellular = self.isCellular
        let wifiTimeout = self.artworkRequestTimeout
        let cellFastTimeout = self.cellularFastTimeout

        artworkTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if Task.isCancelled { return }

            var data = Data()
            var fetchSucceeded = false

            var currentMimeType: String? = nil

            // Helper to perform a short backoff between attempts
            func shortBackoff() async {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            }

            attemptLoop: for attempt in 0..<2 { // bounded: at most 1 retry
                if Task.isCancelled { return }
                data.removeAll(keepingCapacity: false)

                do {
                    // Apply adaptive timeout policy per attempt
                    let appliedTimeout: TimeInterval
                    if onCellular {
                        appliedTimeout = (attempt == 0) ? cellFastTimeout : wifiTimeout
                    } else {
                        appliedTimeout = wifiTimeout
                    }
                    var req = request
                    req.timeoutInterval = appliedTimeout
                    telemetry.networkPolicyApplied(onCellular: onCellular, timeout: appliedTimeout, attempt: attempt)

                    let metricsCollector = MetricsCollector()
                    let session = URLSession(configuration: .default, delegate: metricsCollector, delegateQueue: nil)
                    // Conditional GET validation assurance: ensure caching is enabled and session is non-ephemeral
                    precondition(session.configuration.urlCache != nil, "URLSession must have a URLCache for conditional GET validators.")
                    precondition(URLCache.shared.diskCapacity > 0 || URLCache.shared.memoryCapacity > 0, "URLCache capacities must be > 0 for caching to function.")
                    #if DEBUG
                    precondition(session.configuration.requestCachePolicy != .reloadIgnoringLocalAndRemoteCacheData, "Prod sessions should not be ephemeral when caching is required")
                    #endif

                    let fetchStart = ProcessInfo.processInfo.systemUptime
                    let (bytes, resp) = try await session.bytes(for: req, delegate: metricsCollector)
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

                    // Handle 304 Not Modified by loading cached response data
                    if http.statusCode == 304 {
                        if let cached = URLCache.shared.cachedResponse(for: req),
                           let cachedHTTP = cached.response as? HTTPURLResponse {
                            // Validate cached MIME type
                            if let ct = cachedHTTP.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                                let cachedMime = ct.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ct
                                currentMimeType = cachedMime
                                let allowedMimesRuntime = allowedMimes.intersection(runtimeSupportedMimes)
                                telemetry.artworkMimeSeen(cachedMime)
                                guard allowedMimesRuntime.contains(cachedMime) else {
                                    await MainActor.run { self.sampleAndLogFailure(.mime_unsupported) }
                                    return
                                }
                                let isSuppressed = await MainActor.run { self.suppressedMIMEs.contains(cachedMime) }
                                if isSuppressed {
                                    await MainActor.run { self.sampleAndLogFailure(.format_suppressed) }
                                    return
                                }
                            }
                            data = cached.data
                            let fetchDuration = ProcessInfo.processInfo.systemUptime - fetchStart
                            telemetry.artworkFetchDuration(fetchDuration)
                            telemetry.artworkCacheHit()

                            if let m = metricsCollector.metrics {
                                let analyzed = self.analyzeMetrics(m)
                                telemetry.artworkRedirectApplied(count: analyzed.redirects, finalHost: (analyzed.finalHost ?? finalHost ?? ""))
                                if analyzed.validatorsUsed { telemetry.artworkValidatorsUsed() } else { telemetry.artworkValidatorsMissing() }
                            } else {
                                // Fallback if metrics are unavailable
                                telemetry.artworkRedirectApplied(count: sameHost ? 0 : 1, finalHost: finalHost ?? "")
                            }

                            fetchSucceeded = true
                            break attemptLoop
                        } else {
                            await MainActor.run { self.sampleAndLogFailure(.cache_miss_304) }
                            // NP-024: Perform one immediate re-request bypassing cache/validators
                            var fallbackReq = req
                            fallbackReq.cachePolicy = .reloadIgnoringLocalCacheData
                            fallbackReq.setValue(nil, forHTTPHeaderField: "If-None-Match")
                            fallbackReq.setValue(nil, forHTTPHeaderField: "If-Modified-Since")

                            let metricsCollector2 = MetricsCollector()
                            let session2 = URLSession(configuration: .default, delegate: metricsCollector2, delegateQueue: nil)
                            let (bytes2, resp2) = try await session2.bytes(for: fallbackReq, delegate: metricsCollector2)
                            if Task.isCancelled { return }
                            guard let http2 = resp2 as? HTTPURLResponse, (200...299).contains(http2.statusCode) else {
                                // Fallback failed; give up
                                return
                            }
                            // Stream with cap
                            data.removeAll(keepingCapacity: false)
                            for try await chunk in bytes2 {
                                if Task.isCancelled { return }
                                data.append(chunk)
                                if data.count > maxBytes {
                                    await MainActor.run { self.sampleAndLogFailure(.stream_cap_exceeded) }
                                    return
                                }
                            }
                            let fetchDuration2 = ProcessInfo.processInfo.systemUptime - fetchStart
                            telemetry.artworkFetchDuration(fetchDuration2)
                            telemetry.artworkCacheMiss()
                            telemetry.artworkCache304FallbackSucceeded()
                            if let m2 = metricsCollector2.metrics {
                                let analyzed2 = self.analyzeMetrics(m2)
                                telemetry.artworkRedirectApplied(count: analyzed2.redirects, finalHost: (analyzed2.finalHost ?? finalHost ?? ""))
                                if analyzed2.validatorsUsed { telemetry.artworkValidatorsUsed() } else { telemetry.artworkValidatorsMissing() }
                            } else {
                                telemetry.artworkRedirectApplied(count: sameHost ? 0 : 1, finalHost: finalHost ?? "")
                            }
                            fetchSucceeded = true
                            break attemptLoop
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
                    currentMimeType = mimeType
                    let allowedMimesRuntime = allowedMimes.intersection(runtimeSupportedMimes)
                    telemetry.artworkMimeSeen(mimeType)
                    guard allowedMimesRuntime.contains(mimeType) else {
                        await MainActor.run { self.sampleAndLogFailure(.mime_unsupported) }
                        return
                    }
                    // If this MIME has been suppressed for this session, bail out early
                    let isSuppressed = await MainActor.run { self.suppressedMIMEs.contains(mimeType) }
                    if isSuppressed {
                        await MainActor.run { self.sampleAndLogFailure(.format_suppressed) }
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

                    let fetchDuration = ProcessInfo.processInfo.systemUptime - fetchStart
                    telemetry.artworkFetchDuration(fetchDuration)

                    telemetry.artworkCacheMiss()

                    if let m = metricsCollector.metrics {
                        let analyzed = self.analyzeMetrics(m)
                        telemetry.artworkRedirectApplied(count: analyzed.redirects, finalHost: (analyzed.finalHost ?? finalHost ?? ""))
                        if analyzed.validatorsUsed { telemetry.artworkValidatorsUsed() } else { telemetry.artworkValidatorsMissing() }
                    } else {
                        // Fallback if metrics are unavailable
                        telemetry.artworkRedirectApplied(count: sameHost ? 0 : 1, finalHost: finalHost ?? "")
                    }

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
                if let m = currentMimeType {
                    await MainActor.run {
                        let next = (self.mimeDecodeFailureCounts[m] ?? 0) + 1
                        self.mimeDecodeFailureCounts[m] = next
                        if next >= decodeThreshold && !self.suppressedMIMEs.contains(m) {
                            self.suppressedMIMEs.insert(m)
                            self.sampleAndLogFailure(.format_suppressed)
                        }
                    }
                }
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
                if let m = currentMimeType {
                    await MainActor.run {
                        let next = (self.mimeDecodeFailureCounts[m] ?? 0) + 1
                        self.mimeDecodeFailureCounts[m] = next
                        if next >= decodeThreshold && !self.suppressedMIMEs.contains(m) {
                            self.suppressedMIMEs.insert(m)
                            self.sampleAndLogFailure(.format_suppressed)
                        }
                    }
                }
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
            let bucketPoints: [Int]
            switch self.bucketStrategy {
            case .one:  bucketPoints = [512]
            case .two:  bucketPoints = [256, 512]
            case .three: bucketPoints = [256, 512, 1024]
            }
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

                let control = ArtworkCacheControl()

                // Wrap CGImages as UIImages on the main actor only
                let masterImage = UIImage(cgImage: masterCG, scale: screenScale, orientation: .up)

                // Build a bounded cache (<= 3 buckets) of pre-rendered UIImages on main
                var builtBuckets: [Int: UIImage] = [:]
                for (k, v) in cgBucketImages {
                    builtBuckets[k] = UIImage(cgImage: v, scale: screenScale, orientation: .up)
                }
                control.buckets = builtBuckets

                // Provider-closure invariants:
                // - No UIKit rendering or blocking I/O inside the closure.
                // - Only returns prebuilt UIImages (created on main above).
                // - Cache is bounded (<= 3 buckets: 256/512/1024) and may be purged under memory pressure.
                // - Safe to be called on any thread.

                #if DEBUG
                precondition((control.buckets?.count ?? 0) <= 3, "Artwork cache should be bounded to <= 3 buckets")
                #endif

                let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { requested in
                    // Invariant checks (DEBUG only): do not add rendering or I/O here.
                    #if DEBUG
                    precondition((control.buckets?.count ?? 0) <= 3, "Artwork cache should be bounded to <= 3 buckets")
                    #endif

                    // Record popularity by requested size class (thread-safe, off-main safe)
                    let maxDim = max(requested.width, requested.height)
                    control.metrics.record(requestedMaxDimension: maxDim)

                    // On memory pressure, return master and avoid buckets
                    if control.purge { return masterImage }

                    // Return prebuilt images only; no resizing or UIKit off-main here
                    if requested.equalTo(boundsSize) {
                        return masterImage
                    }
                    let b: Int
                    if maxDim <= 256 { b = 256 }
                    else if maxDim <= 512 { b = 512 }
                    else { b = 1024 }
                    return control.buckets?[b] ?? masterImage
                }

                self.currentArtworkControl = control

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
        pathMonitor.cancel()
        artworkTask?.cancel()
    }
}

