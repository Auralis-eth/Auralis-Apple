import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO
import Network

extension Notification.Name {
    static let nowPlayingLiveStreamStateDidChange = Notification.Name("NowPlayingService.liveStreamStateDidChange")
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

    // NP-025: Configurable bucket strategy
    public enum ArtworkBucketStrategy { case one, two, three }
    private var bucketStrategy: ArtworkBucketStrategy
    
    // NP-049: Cool-down to avoid bucket flapping
    private var bucketStrategyCooldownUntil: Date? = nil
    private let bucketStrategyCooldown: TimeInterval = 300 // 5 minutes

    // Reintroduce URLSession storage (required by initializer usage)
    private let urlSession: URLSession

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
            func reset() {
                q.async { self.le256 = 0; self.le512 = 0; self.gt512 = 0 }
            }
        }
        private let lock = NSLock()
        private var _purge = false
        private var _dropMaster = false
        private var _buckets: [Int: UIImage]? = nil
        private var _master: UIImage? = nil
        private var _placeholder: UIImage? = nil
        let metrics = ProviderMetrics()

        // MARK: Thread-safe accessors
        var purge: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _purge }
            set { lock.lock(); _purge = newValue; lock.unlock() }
        }
        var dropMaster: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _dropMaster }
            set { lock.lock(); _dropMaster = newValue; lock.unlock() }
        }
        var buckets: [Int: UIImage]? {
            get { lock.lock(); defer { lock.unlock() }; return _buckets }
            set { lock.lock(); _buckets = newValue; lock.unlock() }
        }
        var master: UIImage? {
            get { lock.lock(); defer { lock.unlock() }; return _master }
            set { lock.lock(); _master = newValue; lock.unlock() }
        }
        var placeholder: UIImage? {
            get { lock.lock(); defer { lock.unlock() }; return _placeholder }
            set { lock.lock(); _placeholder = newValue; lock.unlock() }
        }

        func imageFor(requested: CGSize, boundsSize: CGSize) -> UIImage? {
            lock.lock()
            let purge = _purge
            let dropMaster = _dropMaster
            let master = _master
            let placeholder = _placeholder
            let buckets = _buckets
            lock.unlock()

            if purge {
                // On purge, avoid bucket usage. Optionally drop master if requested.
                if dropMaster { return placeholder ?? master }
                return master
            }
            // Exact match returns master
            if requested.equalTo(boundsSize) { return master }
            let maxDim = max(requested.width, requested.height)
            let b: Int
            if maxDim <= 256 { b = 256 }
            else if maxDim <= 512 { b = 512 }
            else { b = 1024 }
            if let img = buckets?[b] { return img }
            return master
        }
    }
    private var currentArtworkControl: ArtworkCacheControl?

    private var lastPublishedElapsed: TimeInterval?
    private var lastPublishedRate: Double?
    private var lastIsLive: Bool? = nil

    private let artworkRequestTimeout: TimeInterval = 5
    private let artworkMaxBytes: Int = 10 * 1024 * 1024 // 10 MB cap
    private let allowedImageMIMETypes: Set<String> = ["image/jpeg", "image/jpg", "image/pjpeg", "image/png", "image/webp", "image/heic", "image/heif"]
    private var artworkMasterMaxPixelSize: CGFloat = 1024
    private let allowedRedirectHosts: Set<String>?
    // T-NP-001: Optional organizational-domain allow-list (parent domains)
    private let allowedRedirectOrgDomains: Set<String>?

    private let runtimeSupportedMIMEs: Set<String>
    // T-NP-002: EWMA per-host for first-attempt cellular timeout
    private var hostLatencyEWMA: [String: TimeInterval] = [:]
    private let ewmaAlpha: Double = 0.3
    private let minFirstAttemptCellularTimeout: TimeInterval = 1.0
    private let maxFirstAttemptCellularTimeout: TimeInterval = 5.0

    private var mimeDecodeFailureCounts: [String: Int] = [:]
    private let decodeSuppressionThreshold: Int = 3

    private var memoryWarningObserver: NSObjectProtocol?
    private var bgObserver: NSObjectProtocol?
    private var fgObserver: NSObjectProtocol?
    private var isBackgrounded: Bool = false
    private var consecutiveMemoryWarnings: Int = 0
    private let memoryWarningWindow: TimeInterval = 60
    private var lastMemoryWarningTime: TimeInterval = 0
    private var lastPlaceholderImage: UIImage? = nil
    // T-NP-004: MIME suppression LRU cap
    private let mimeSuppressionCap: Int = 128

    private let mimeSuppressionTTL: TimeInterval = 1800 // 30 minutes
    private var suppressedMIMEUntil: [String: Date] = [:]

    // NP-046: Cap size for validator-missing host map (LRU eviction by oldest timestamp)
    private var isCellular: Bool = false
    // T-NP-003: Bucket rehydration cooldown
    private let bucketRehydrateCooldown: TimeInterval = 20
    private var bucketRehydrateUntil: Date? = nil

    private let cellularFastTimeout: TimeInterval = 2.0
    private let cellularTimeoutOverrideHosts: Set<String>?

    private var pathMonitor: NWPathMonitor? = nil
    private let pathMonitorQueue = DispatchQueue(label: "NowPlayingService.Network")
    private var pathMonitorStarted: Bool = false
    private var pathMonitorIdleTimer: DispatchSourceTimer?
    private let pathMonitorIdleGrace: TimeInterval = 120

    nonisolated private static func host(_ host: String, isSubdomainOf parent: String) -> Bool {
        let h = host.lowercased()
        let p = parent.lowercased()
        return h == p || h.hasSuffix("." + p)
    }

    private func updateEWMA(for host: String, sample seconds: TimeInterval) {
        guard !host.isEmpty, seconds.isFinite, seconds > 0 else { return }
        let prev = hostLatencyEWMA[host] ?? cellularFastTimeout
        let next = (ewmaAlpha * seconds) + ((1.0 - ewmaAlpha) * prev)
        hostLatencyEWMA[host] = min(max(next, minFirstAttemptCellularTimeout), maxFirstAttemptCellularTimeout)
    }

    // Apply a coherent Now Playing bundle in a single assignment to avoid partial state
    private func applyNowPlaying(_ build: (inout [String: Any]) -> Void) {
        var snapshot = info
        build(&snapshot)
        info = snapshot
        center.nowPlayingInfo = snapshot
    }

    // NP-048: Start path monitor lazily
    private func startPathMonitorIfNeeded() {
        if !pathMonitorStarted {
            let monitor = NWPathMonitor()
            self.pathMonitor = monitor

            // T-NP-009: Prime network type from current path and emit telemetry
            let primedOnCell = monitor.currentPath.isExpensive
            self.isCellular = primedOnCell

            monitor.pathUpdateHandler = { [weak self] path in
                // Changed line as per instructions:
                let onCell = path.isExpensive

                // Mutate actor-isolated state on the main actor
                Task { @MainActor [weak self] in
                    self?.isCellular = onCell
                }
            }
            monitor.start(queue: pathMonitorQueue)
            pathMonitorStarted = true
        }
        // Reset idle timer when activity occurs
        schedulePathMonitorStop()
    }

    // NP-048: Schedule stop after idle grace
    private func schedulePathMonitorStop() {
        // Cancel any existing timer
        if let t = pathMonitorIdleTimer {
            t.cancel()
            pathMonitorIdleTimer = nil
        }

        // Create a queue-backed timer to avoid run-loop mode deferrals
        let timer = DispatchSource.makeTimerSource(queue: pathMonitorQueue)
        timer.schedule(deadline: .now() + pathMonitorIdleGrace, repeating: .never)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                if let monitor = self.pathMonitor, self.pathMonitorStarted {
                    monitor.cancel()
                }
                self.pathMonitorStarted = false
                self.pathMonitor = nil
                // Ensure timer is torn down
                self.pathMonitorIdleTimer?.cancel()
                self.pathMonitorIdleTimer = nil
            }
        }
        pathMonitorIdleTimer = timer
        timer.resume()
    }

    private func handleMemoryPressure() {
        // Signal current artwork provider to purge bucket images; keep master only by default
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMemoryWarningTime > memoryWarningWindow { consecutiveMemoryWarnings = 0 }
        lastMemoryWarningTime = now
        consecutiveMemoryWarnings += 1

        if let control = currentArtworkControl {
            control.purge = true
            control.buckets = nil
            // NP-039/NP-042/NP-045/NP-055:
            // Policy: Before allowing master-drop while paused/backgrounded with repeated warnings,
            // ensure a placeholder exists so artwork never goes blank. We proactively create a
            // lightweight placeholder if needed just-in-time, then allow dropping the master.
            let paused = (lastPublishedRate ?? 1.0) == 0.0
            if (isBackgrounded || paused) && consecutiveMemoryWarnings >= 2 {
                self.ensurePlaceholderAvailable(on: control)
                control.dropMaster = true
                // T-NP-003: Start rehydration cooldown when master is dropped
                self.bucketRehydrateUntil = Date().addingTimeInterval(self.bucketRehydrateCooldown)
            }
        }
    }

    private static func detectRuntimeSupportedMIMEs() -> Set<String> {
        var supported: Set<String> = ["image/jpeg", "image/jpg", "image/pjpeg", "image/png"]
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

    // Tiny 1x1 fallback image to guarantee non-nil provider returns
    private lazy var tinyFallbackImage: UIImage = {
        let size = CGSize(width: 1, height: 1)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.systemGray5.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }()

    // Build a very lightweight placeholder artwork using a solid color image
    private func buildPlaceholderArtwork(for url: URL, scale: CGFloat) -> MPMediaItemArtwork {
        // Keep the logical bounds at a typical square; image itself is tiny to minimize memory
        let boundsSize = CGSize(width: 512, height: 512)
        let color = placeholderColor(for: url)
        let pointSize = CGSize(width: max(1, 32), height: max(1, 32))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(1, scale)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let img = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: pointSize))
        }
        // Retain for low-memory fallback
        self.lastPlaceholderImage = img

        let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { _ in
            return img
        }
        return artwork
    }

    // Ensure a placeholder UIImage exists on the control; create a generic one if needed
    private func ensurePlaceholderAvailable(on control: ArtworkCacheControl) {
        if control.placeholder == nil {
            if let existing = self.lastPlaceholderImage {
                control.placeholder = existing
            } else {
                // Build a generic solid-color placeholder (no URL context)
                let size = CGSize(width: 32, height: 32)
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = max(1, UIScreen.main.scale)
                format.opaque = true
                let renderer = UIGraphicsImageRenderer(size: size, format: format)
                let img = renderer.image { ctx in
                    UIColor.systemGray5.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                }
                self.lastPlaceholderImage = img
                control.placeholder = img
            }
        }
    }

    private func enforceMimeSuppressionCap() {
        if suppressedMIMEUntil.count <= mimeSuppressionCap { return }
        // Evict by oldest `until` date (approximate LRU of offenders)
        let over = suppressedMIMEUntil.count - mimeSuppressionCap
        let sorted = suppressedMIMEUntil.sorted { $0.value < $1.value }
        for i in 0..<min(over, sorted.count) {
            suppressedMIMEUntil.removeValue(forKey: sorted[i].key)
        }
    }

    public init(center: NowPlayingCentering = DefaultNowPlayingCenter(),
                cadence: TimeInterval = 5.0,
                decodeMaxPixelSize: CGFloat? = nil,
                allowedRedirectHosts: Set<String>? = nil,
                bucketStrategy: ArtworkBucketStrategy = .two,
                cellularTimeoutOverrideHosts: Set<String>? = nil,
                allowedRedirectOrgDomains: Set<String>? = nil) {
        self.center = center
        self.cadence = max(0.5, cadence)
        self.allowedRedirectHosts = allowedRedirectHosts
        self.allowedRedirectOrgDomains = allowedRedirectOrgDomains
        self.bucketStrategy = bucketStrategy
        self.cellularTimeoutOverrideHosts = cellularTimeoutOverrideHosts
        if let decodeMaxPixelSize, decodeMaxPixelSize > 0 {
            self.artworkMasterMaxPixelSize = decodeMaxPixelSize
        }
        self.runtimeSupportedMIMEs = NowPlayingService.detectRuntimeSupportedMIMEs()

        // NP-035: Reuse a single cache-enabled URLSession
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .useProtocolCachePolicy
        // Ensure URLCache exists and has capacity
        if cfg.urlCache == nil { cfg.urlCache = URLCache.shared }
        if URLCache.shared.memoryCapacity == 0 && URLCache.shared.diskCapacity == 0 {
            // NP-034: In release, emit telemetry and set safe defaults; in debug, assert
            #if DEBUG
            assertionFailure("URLCache capacities must be > 0 for caching to function.")
            #else
            URLCache.shared.memoryCapacity = 8 * 1024 * 1024
            URLCache.shared.diskCapacity = 64 * 1024 * 1024
            #endif
        }
        #if DEBUG
        assert(cfg.requestCachePolicy != .reloadIgnoringLocalAndRemoteCacheData, "Prod sessions should not be ephemeral when caching is required")
        #else
        if cfg.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData {
            cfg.requestCachePolicy = .useProtocolCachePolicy
        }
        #endif
        self.urlSession = URLSession(configuration: cfg, delegate: nil, delegateQueue: nil)
        if self.urlSession.configuration.urlCache == nil {
            #if DEBUG
            assertionFailure("URLSession must have a URLCache for conditional GET validators.")
            #endif
        }

        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleMemoryPressure()
        }
        bgObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isBackgrounded = true
        }
        fgObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isBackgrounded = false
            self?.consecutiveMemoryWarnings = 0
        }
    }
    
    private func bucketCount(_ s: ArtworkBucketStrategy) -> Int {
        switch s { case .one: return 1; case .two: return 2; case .three: return 3 }
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
                return
            }
        }

        // NP-050: Mirror default playback rate behavior in updateProgress
        let hasDefault = info[MPNowPlayingInfoPropertyDefaultPlaybackRate] != nil

        // Publish progress update now as a coherent bundle
        lastProgressUptime = nowUptime
        applyNowPlaying {
            $0[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
            $0[MPNowPlayingInfoPropertyPlaybackRate] = rate
            if rate > 0 {
                if !hasDefault {
                    // NP-050: Ensure default rate exists when transitioning to playing
                    $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                }
            } else {
                // NP-050: Remove default when paused
                $0.removeValue(forKey: MPNowPlayingInfoPropertyDefaultPlaybackRate)
            }
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
            if rate > 0 {
                if let defaultRate {
                    $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = defaultRate
                } else {
                    // NP-050: Ensure default rate is present when playing
                    $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                }
            } else {
                // NP-050: Omit default when paused to avoid confusing surfaces
                $0.removeValue(forKey: MPNowPlayingInfoPropertyDefaultPlaybackRate)
            }
        }

        // T-NP-011: Notify app UI about live stream state changes to align scrubber affordances
        let isLive = safeDuration <= 0
        if lastIsLive != isLive {
            lastIsLive = isLive
            NotificationCenter.default.post(name: .nowPlayingLiveStreamStateDidChange, object: self, userInfo: ["isLive": isLive])
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

    /// Clear any temporarily suppressed MIME types so future attempts can decode again immediately.
    public func clearSuppressedMIMEs() {
        suppressedMIMEUntil.removeAll()
    }

    public func setArtwork(from urlString: String?) {
        // Cancel any in-flight artwork fetch/decode
        artworkTask?.cancel()
        artworkTask = nil

        guard let s = urlString, let url = URL(string: s) else { return }
        // Enforce HTTPS only
        guard url.scheme?.lowercased() == "https" else { return }

        // NP-048: Ensure path monitor is running for adaptive policy
        startPathMonitorIfNeeded()

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
        request.setValue("image/*", forHTTPHeaderField: "Accept") // inserted as per instructions

        // Capture UI-related values on the main actor for use off-main
        let screenScale = UIScreen.main.scale
        let decodeCap = self.artworkMasterMaxPixelSize
        let allowedMimes = self.allowedImageMIMETypes
        let maxBytes = self.artworkMaxBytes
        let originalHost = url.host?.lowercased()
        let redirectAllowlist = self.allowedRedirectHosts?.map { $0.lowercased() }
        let orgDomains = self.allowedRedirectOrgDomains?.map { $0.lowercased() }
        let runtimeSupportedMimes = self.runtimeSupportedMIMEs
        let decodeThreshold = self.decodeSuppressionThreshold
        let onCellular = self.isCellular
        let wifiTimeout = self.artworkRequestTimeout
        let timeoutOverrideHosts = self.cellularTimeoutOverrideHosts?.map { $0.lowercased() }

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
                    // Apply adaptive timeout policy per attempt (NP-047 host-aware override)
                    let appliedTimeout: TimeInterval
                    if onCellular {
                        let host = originalHost
                        let overrideFast = (host != nil) && (timeoutOverrideHosts?.contains(host!) ?? false)
                        if overrideFast {
                            appliedTimeout = wifiTimeout
                        } else {
                            if attempt == 0 {
                                // T-NP-002: Adapt first-attempt timeout using EWMA per-host
                                let base = await MainActor.run { () -> TimeInterval in
                                    let h = host ?? ""
                                    let est = (!h.isEmpty) ? (self.hostLatencyEWMA[h] ?? self.cellularFastTimeout) : self.cellularFastTimeout
                                    return est
                                }
                                let clamped = min(max(base, self.minFirstAttemptCellularTimeout), self.maxFirstAttemptCellularTimeout)
                                appliedTimeout = clamped
                            } else {
                                appliedTimeout = wifiTimeout
                            }
                        }
                    } else {
                        appliedTimeout = wifiTimeout
                    }
                    var req = request
                    req.timeoutInterval = appliedTimeout

                    let session = self.urlSession
                    #if DEBUG
                    assert(session.configuration.urlCache != nil, "URLSession must have a URLCache for conditional GET validators.")
                    #endif

                    let fetchStart = ProcessInfo.processInfo.systemUptime
                    let (bytes, resp) = try await session.bytes(for: req, delegate: nil)
                    if Task.isCancelled { return }
                    guard let http = resp as? HTTPURLResponse else {
                        return
                    }
                    // Enforce redirect/host policy: final URL must be https and same-host or allowlisted
                    let finalURL = http.url
                    let finalSchemeOK = finalURL?.scheme?.lowercased() == "https"
                    let finalHost = finalURL?.host?.lowercased()
                    let sameHost = (finalHost != nil && finalHost == originalHost)
                    let inAllowlist = (finalHost != nil && (redirectAllowlist?.contains(finalHost!) ?? false))
                    let inOrgDomain: Bool = {
                        guard let finalHost, let orgs = orgDomains, !orgs.isEmpty else { return false }
                        for p in orgs {
                            if NowPlayingService.host(finalHost, isSubdomainOf: p) {
                                return true
                        }
                        }
                        return false
                    }()
                    if !(finalSchemeOK && (sameHost || inAllowlist || inOrgDomain)) {
                        return
                    }

                    // Handle 304 Not Modified by loading cached response data
                    if http.statusCode == 304 {
                        if let cache = session.configuration.urlCache,
                           let cached = cache.cachedResponse(for: req),
                           let cachedHTTP = cached.response as? HTTPURLResponse {
                            // Validate cached MIME type
                            if let ct = cachedHTTP.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                                let cachedMime = ct.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ct
                                currentMimeType = cachedMime
                                let allowedMimesRuntime = allowedMimes.intersection(runtimeSupportedMimes)
                                let isSuppressed = await MainActor.run { () -> Bool in
                                    if let until = self.suppressedMIMEUntil[cachedMime], until > Date() {
                                        return true
                                    } else if let until = self.suppressedMIMEUntil[cachedMime], until <= Date() {
                                        self.suppressedMIMEUntil.removeValue(forKey: cachedMime)
                                        self.enforceMimeSuppressionCap()
                                        return false
                                    }
                                    return false
                                }
                                guard allowedMimesRuntime.contains(cachedMime) else {
                                    return
                                }
                                if isSuppressed {
                                    return
                                }
                            }
                            data = cached.data
                            let fetchDuration = ProcessInfo.processInfo.systemUptime - fetchStart

                            if let h = finalHost ?? originalHost {
                                await MainActor.run { self.updateEWMA(for: h, sample: fetchDuration) }
                            }

                            fetchSucceeded = true
                        } else if let cached = URLCache.shared.cachedResponse(for: req),
                                  let cachedHTTP = cached.response as? HTTPURLResponse {
                            // Validate cached MIME type
                            if let ct = cachedHTTP.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                                let cachedMime = ct.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ct
                                currentMimeType = cachedMime
                                let allowedMimesRuntime = allowedMimes.intersection(runtimeSupportedMimes)
                                let isSuppressed = await MainActor.run { () -> Bool in
                                    if let until = self.suppressedMIMEUntil[cachedMime], until > Date() {
                                        return true
                                    } else if let until = self.suppressedMIMEUntil[cachedMime], until <= Date() {
                                        self.suppressedMIMEUntil.removeValue(forKey: cachedMime)
                                        self.enforceMimeSuppressionCap()
                                        return false
                                    }
                                    return false
                                }
                                guard allowedMimesRuntime.contains(cachedMime) else {
                                    return
                                }
                                if isSuppressed {
                                    return
                                }
                            }
                            data = cached.data
                            let fetchDuration = ProcessInfo.processInfo.systemUptime - fetchStart

                            if let h = finalHost ?? originalHost {
                                await MainActor.run { self.updateEWMA(for: h, sample: fetchDuration) }
                            }

                            fetchSucceeded = true
                        } else {
                            // NP-024: Perform one immediate re-request bypassing cache/validators
                            var fallbackReq = req
                            fallbackReq.cachePolicy = .reloadIgnoringLocalCacheData
                            fallbackReq.setValue(nil, forHTTPHeaderField: "If-None-Match")
                            fallbackReq.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
                            fallbackReq.setValue("image/*", forHTTPHeaderField: "Accept") // inserted as per instructions

                            let session2 = self.urlSession
                            #if DEBUG
                            assert(session2.configuration.urlCache != nil, "URLSession must have a URLCache for conditional GET validators.")
                            #endif

                            let (bytes2, resp2) = try await session2.bytes(for: fallbackReq, delegate: nil)

                            // T-NP-013: Enforce redirect/HTTPS policy on 304 fallback as invariant
                            if let http2 = resp2 as? HTTPURLResponse {
                                let finalURL2 = http2.url
                                let finalSchemeOK2 = finalURL2?.scheme?.lowercased() == "https"
                                let finalHost2 = finalURL2?.host?.lowercased()
                                let sameHost2 = (finalHost2 != nil && finalHost2 == originalHost)
                                let inAllowlist2 = (finalHost2 != nil && (redirectAllowlist?.contains(finalHost2!) ?? false))
                                let inOrgDomain2: Bool = {
                                    guard let finalHost2, let orgs = orgDomains, !orgs.isEmpty else { return false }
                                    for p in orgs { if NowPlayingService.host(finalHost2, isSubdomainOf: p) { return true } }
                                    return false
                                }()
                                let respected = finalSchemeOK2 && (sameHost2 || inAllowlist2 || inOrgDomain2)
                                #if DEBUG
                                if !respected { assertionFailure("Redirect/HTTPS policy must be respected on 304 fallback") }
                                #endif
                                if !respected { return }
                            }

                            // Stream with cap
                            data.removeAll(keepingCapacity: false)
                            for try await chunk in bytes2 {
                                if Task.isCancelled { return }
                                data.append(chunk)
                                if data.count > maxBytes {
                                    return
                                }
                            }
                            let fetchDuration2 = ProcessInfo.processInfo.systemUptime - fetchStart
                            if let h = finalHost ?? originalHost {
                                await MainActor.run { self.updateEWMA(for: h, sample: fetchDuration2) }
                            }
                            fetchSucceeded = true
                        }
                        break attemptLoop
                    }
                    // Non-success status handling with transient retry for 5xx only
                    guard (200...299).contains(http.statusCode) else {
                        if (500...599).contains(http.statusCode), attempt == 0 {
                            await shortBackoff()
                            continue attemptLoop
                        } else {
                            return
                        }
                    }
                    // Validate MIME type early
                    guard let contentTypeHeader = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
                        return
                    }
                    let mimeType = contentTypeHeader.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentTypeHeader
                    currentMimeType = mimeType
                    let allowedMimesRuntime = allowedMimes.intersection(runtimeSupportedMimes)
                    let isSuppressed = await MainActor.run { () -> Bool in
                        if let until = self.suppressedMIMEUntil[mimeType], until > Date() {
                            return true
                        } else if let until = self.suppressedMIMEUntil[mimeType], until <= Date() {
                            self.suppressedMIMEUntil.removeValue(forKey: mimeType)
                            self.enforceMimeSuppressionCap()
                            return false
                        }
                        return false
                    }
                    guard allowedMimesRuntime.contains(mimeType) else {
                        return
                    }
                    if isSuppressed {
                        return
                    }
                    // Enforce Content-Length if provided
                    if let lenStr = http.value(forHTTPHeaderField: "Content-Length"), let len = Int(lenStr), len > maxBytes {
                        return
                    }
                    // Stream with hard cap
                    for try await chunk in bytes {
                        if Task.isCancelled { return }
                        data.append(chunk)
                        if data.count > maxBytes {
                            return
                        }
                    }

                    let fetchDuration = ProcessInfo.processInfo.systemUptime - fetchStart
                    // Fallback if metrics are unavailable
                    if let h = finalHost ?? originalHost {
                        await MainActor.run { self.updateEWMA(for: h, sample: fetchDuration) }
                    }

                    // If we made it here, fetch succeeded
                    fetchSucceeded = true
                    break attemptLoop
                } catch {
                    if Task.isCancelled { return }
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

            // Decode once into a bounded master CGImage using ImageIO (no UIKit off-main)
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else {
                if let m = currentMimeType {
                    await MainActor.run {
                        let next = (self.mimeDecodeFailureCounts[m] ?? 0) + 1
                        self.mimeDecodeFailureCounts[m] = next
                        if next >= decodeThreshold {
                            self.suppressedMIMEUntil[m] = Date().addingTimeInterval(self.mimeSuppressionTTL)
                            self.enforceMimeSuppressionCap()
                        }
                    }
                }
                return
            }

            let masterOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: decodeCap * screenScale
            ]
            guard let masterCG = CGImageSourceCreateThumbnailAtIndex(src, 0, masterOpts as CFDictionary) else {
                if let m = currentMimeType {
                    await MainActor.run {
                        let next = (self.mimeDecodeFailureCounts[m] ?? 0) + 1
                        self.mimeDecodeFailureCounts[m] = next
                        if next >= decodeThreshold {
                            self.suppressedMIMEUntil[m] = Date().addingTimeInterval(self.mimeSuppressionTTL)
                            self.enforceMimeSuppressionCap()
                        }
                    }
                }
                return
            }

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
            let strategy = await MainActor.run { self.bucketStrategy }
            switch strategy {
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
                let now = Date()
                let shouldDefer = ((self.bucketRehydrateUntil != nil && now < self.bucketRehydrateUntil!) || self.isBackgrounded || ((self.lastPublishedRate ?? 0) == 0))
                if shouldDefer {
                    control.buckets = nil
                } else {
                    control.buckets = builtBuckets
                }
                control.master = masterImage
                control.placeholder = self.lastPlaceholderImage

                // NP-041/NP-049: Adaptive bucket strategy with cool-down to avoid flapping
                if let prev = self.currentArtworkControl {
                    let s = prev.metrics.snapshot()
                    let total = s.le256 + s.le512 + s.gt512
                    if total >= 20 {
                        let small = s.le256 + s.le512
                        let ratio = Double(small) / Double(max(1, total))
                        var proposed: ArtworkBucketStrategy? = nil
                        if ratio >= 0.9 {
                            proposed = (s.gt512 == 0 && s.le512 > 0 && s.le256 == 0) ? .one : .two
                        }
                        if let proposed {
                            let current = self.bucketStrategy
                            let now = Date()
                            let currentCount = self.bucketCount(current)
                            let proposedCount = self.bucketCount(proposed)
                            if proposedCount > currentCount {
                                // Up-shift: only allow if cooldown has elapsed
                                if let until = self.bucketStrategyCooldownUntil, until > now {
                                    // skip up-shift during cooldown
                                } else {
                                    self.bucketStrategy = proposed
                                }
                            } else if proposedCount < currentCount {
                                // Down-shift: apply and set cooldown window
                                self.bucketStrategy = proposed
                                self.bucketStrategyCooldownUntil = now.addingTimeInterval(self.bucketStrategyCooldown)
                            } // equal -> no change
                        }
                    }
                }

                // Provider-closure invariants:
                // - No UIKit rendering or blocking I/O inside the closure.
                // - Only returns prebuilt UIImages (created on main above).
                // - Cache is bounded (<= 3 buckets: 256/512/1024) and may be purged under memory pressure.
                // - Safe to be called on any thread.

                #if DEBUG
                precondition((control.buckets?.count ?? 0) <= 3, "Artwork cache should be bounded to <= 3 buckets")
                #endif

                let providerFallbackImage = control.placeholder ?? control.master ?? self.tinyFallbackImage

                let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { requested in
                    // Invariant checks (DEBUG only): do not add rendering or I/O here.
                    #if DEBUG
                    precondition((control.buckets?.count ?? 0) <= 3, "Artwork cache should be bounded to <= 3 buckets")
                    #endif

                    // Record popularity by requested size class (thread-safe, off-main safe)
                    let maxDim = max(requested.width, requested.height)
                    control.metrics.record(requestedMaxDimension: maxDim)

                    return control.imageFor(requested: requested, boundsSize: boundsSize) ?? providerFallbackImage
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

        // NP-043: Clear provider state so buckets/master can be released immediately
        currentArtworkControl = nil

        // NP-048: Service likely idle; schedule monitor stop after grace
        schedulePathMonitorStop()
    }

    deinit {
        pathMonitor?.cancel()
        pathMonitorIdleTimer?.cancel()
        pathMonitorIdleTimer = nil
        artworkTask?.cancel()
        if let token = memoryWarningObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = bgObserver { NotificationCenter.default.removeObserver(token) }
        if let token = fgObserver { NotificationCenter.default.removeObserver(token) }
    }
}

