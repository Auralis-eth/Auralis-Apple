import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO
import Network

@MainActor
public final class NowPlayingService {
    // MARK: - Network Path Monitoring
    private var pathMonitor: NWPathMonitor? = nil
    private var pathMonitorStarted: Bool = false
    private let pathMonitorQueue = DispatchQueue(label: "NowPlayingService.PathMonitor", qos: .utility)
    private var pathMonitorIdleTimer: DispatchSourceTimer? = nil
    private let pathMonitorIdleGrace: TimeInterval = 30 // seconds of idle before stopping monitor
    // Queue-serialized active flag to avoid start/stop races
    private var pathMonitorActiveFlag: Bool = false

    // Path state captured from NWPathMonitor
    private var isCellular: Bool = false
    private var hasPathUpdate: Bool = false

    // MARK: - App Lifecycle / Memory Pressure
    private var memoryWarningObserver: NSObjectProtocol? = nil
    private var bgObserver: NSObjectProtocol? = nil
    private var fgObserver: NSObjectProtocol? = nil
    private var raObserver: NSObjectProtocol? = nil
    private var termObserver: NSObjectProtocol? = nil
    private var isBackgrounded: Bool = false

    private var lastMemoryWarningTime: TimeInterval = 0
    private let memoryWarningWindow: TimeInterval = 60 // seconds to group warnings
    private var consecutiveMemoryWarnings: Int = 0

    // MARK: - Artwork / Placeholder cache
    private var lastPlaceholderImage: UIImage? = nil

    // MARK: - MIME Suppression / Decode failure tracking
    private var suppressedMIMEUntil: [String: Date] = [:]
    private var mimeDecodeFailureCounts: [String: Int] = [:]
    private let mimeSuppressionTTL: TimeInterval = 3600 // 1 hour suppression for problematic MIME types
    private let mimeSuppressionCap: Int = 64 // cap number of suppressed MIME entries
    private let decodeSuppressionThreshold: Int = 3 // consecutive decode failures before suppression

    // MARK: - Cellular timeout policy
    private let cellularFastTimeout: TimeInterval = 1.5 // default first-attempt timeout on cellular when no EWMA
    private let cellularTimeoutOverrideHosts: Set<String>?

    // MARK: - Bucket rehydration policy (after memory pressure)
    private var bucketRehydrateUntil: Date? = nil
    private let bucketRehydrateCooldown: TimeInterval = 60 // seconds to defer bucket rehydration

    // Normalize a host to ASCII (IDNA/punycode) using Foundation URL parsing; returns lowercased ASCII or nil
    nonisolated private static func normalizeHostASCII(_ host: String) -> String? {
        guard !host.isEmpty else { return nil }
        // Build a URL and read back the host; Foundation will normalize IDNs to punycode ASCII
        if let url = URL(string: "https://\(host)/"), let h = url.host { return h.lowercased() }
        // Fallback: try URLComponents as a second attempt
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        if let h = comps.url?.host { return h.lowercased() }
        return host.lowercased()
    }

    // Strict subdomain check: host must be a real subdomain of parent (not equal), with dot boundary
    nonisolated private static func isStrictSubdomain(_ host: String, of parent: String) -> Bool {
        let h = host.lowercased()
        let p = parent.lowercased()
        return h != p && h.hasSuffix("." + p)
    }

    nonisolated private static func host(_ host: String, isSubdomainOf parent: String) -> Bool {
        let h = host.lowercased()
        let p = parent.lowercased()
        return h == p || h.hasSuffix("." + p)
    }
    
    // Compute a conservative eTLD+1 using a small set of common multi-label public suffixes
    nonisolated private static func effectiveTLDPlusOne(_ host: String) -> String? {
        let h = normalizeHostASCII(host) ?? ""
        guard !h.isEmpty else { return nil }
        let labels = h.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return h }
        // Common multi-label public suffixes; extend conservatively as needed
        let multiLabelSuffixes: Set<String> = [
            "co.uk", "org.uk", "gov.uk", "ac.uk",
            "com.au", "net.au", "org.au", "edu.au",
            "co.jp", "ne.jp", "or.jp",
            "co.nz", "org.nz", "govt.nz"
        ]
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if multiLabelSuffixes.contains(lastTwo), labels.count >= 3 {
            // eTLD is two labels (e.g., co.uk); eTLD+1 is last three labels
            return labels.suffix(3).joined(separator: ".")
        } else {
            // Default for single-label TLDs: return the registrable domain (last two labels)
            return lastTwo
        }
    }
    
    nonisolated static let bucketThresholds: [Int] = [256, 512, 1024]
    nonisolated static let bucketBias: CGFloat = 1.10

    nonisolated private static func isFinalURLAllowed(finalURL: URL?, originalHostASCII: String?, redirectAllowlist: [String]?, orgDomains: [String]?) -> (allowed: Bool, finalHostASCII: String?) {
        guard let url = finalURL, url.scheme?.lowercased() == "https" else { return (false, nil) }
        let finalHostRaw = url.host
        let finalHostASCII = finalHostRaw.flatMap { normalizeHostASCII($0) }
        guard let fh = finalHostASCII else { return (false, nil) }
        // Same host
        if let orig = originalHostASCII, fh == orig { return (true, fh) }
        // Explicit allow-list
        if let list = redirectAllowlist, list.contains(fh) { return (true, fh) }
        // Organizational domain: strict subdomain + matching eTLD+1
        if let orgs = orgDomains, !orgs.isEmpty {
            if let fhETLD1 = effectiveTLDPlusOne(fh) {
                for p in orgs {
                    if isStrictSubdomain(fh, of: p), let pETLD1 = effectiveTLDPlusOne(p), pETLD1 == fhETLD1 {
                        return (true, fh)
                    }
                }
            }
        }
        return (false, fh)
    }

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

    public enum ArtworkBucketStrategy { case one, two, three }
    private var bucketStrategy: ArtworkBucketStrategy
    
    private var bucketStrategyCooldownUntil: Date? = nil
    private let bucketStrategyCooldown: TimeInterval = 300 // 5 minutes

    // Reintroduce URLSession storage (required by initializer usage)
    private let urlSession: URLSession
    private let artworkURLCache: URLCache

    private var currentArtworkControl: ArtworkCacheControl?

    private var lastPublishedElapsed: TimeInterval?
    private var lastPublishedRate: Double?
    private var lastIsLive: Bool? = nil

    private let artworkRequestTimeout: TimeInterval = 5
    private let artworkMaxBytes: Int = 10 * 1024 * 1024 // 10 MB cap
    private let allowedImageMIMETypes: Set<String> = ["image/jpeg", "image/jpg", "image/pjpeg", "image/png", "image/webp", "image/heic", "image/heif"]
    private var artworkMasterMaxPixelSize: CGFloat = 1024
    private let allowedRedirectHosts: Set<String>?
    private let allowedRedirectOrgDomains: Set<String>?

    private let runtimeSupportedMIMEs: Set<String>
    private var hostLatencyEWMA: [String: TimeInterval] = [:]
    private let ewmaAlpha: Double = 0.3
    private let minFirstAttemptCellularTimeout: TimeInterval = 1.0
    private let maxFirstAttemptCellularTimeout: TimeInterval = 5.0

    private var hostLastSeen: [String: Date] = [:]
    private let ewmaInactivityTTL: TimeInterval = 1800 // 30 minutes
    private let ewmaMaxHosts: Int = 256

    private let ewmaPersistKey = "NowPlayingService.EWMA.v1"
    private struct HostEWMAEntry: Codable { let host: String; let ewma: Double; let lastSeen: Date }
    private func persistEWMA(now: Date = Date()) {
        // Prepare bounded, TTL-pruned snapshot
        var entries: [HostEWMAEntry] = []
        for (host, value) in hostLatencyEWMA {
            if let ts = hostLastSeen[host], now.timeIntervalSince(ts) <= ewmaInactivityTTL {
                entries.append(HostEWMAEntry(host: host, ewma: value, lastSeen: ts))
            }
        }
        // Cap to max hosts by most recent
        entries.sort { $0.lastSeen > $1.lastSeen }
        if entries.count > ewmaMaxHosts { entries = Array(entries.prefix(ewmaMaxHosts)) }
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: ewmaPersistKey)
        } catch {
            // Ignore persistence errors
        }
    }
    private func restoreEWMA(now: Date = Date()) {
        guard let data = UserDefaults.standard.data(forKey: ewmaPersistKey) else { return }
        do {
            let entries = try JSONDecoder().decode([HostEWMAEntry].self, from: data)
            var restored: [String: TimeInterval] = [:]
            var seen: [String: Date] = [:]
            for e in entries {
                if now.timeIntervalSince(e.lastSeen) <= ewmaInactivityTTL {
                    restored[e.host] = min(max(e.ewma, minFirstAttemptCellularTimeout), maxFirstAttemptCellularTimeout)
                    seen[e.host] = e.lastSeen
                }
            }
            // Cap to max hosts by most recent
            let sorted = seen.sorted { $0.value > $1.value }
            let limited = sorted.prefix(ewmaMaxHosts)
            self.hostLatencyEWMA = Dictionary(uniqueKeysWithValues: limited.map { ($0.key, restored[$0.key] ?? cellularFastTimeout) })
            self.hostLastSeen = Dictionary(uniqueKeysWithValues: limited.map { ($0.key, $0.value) })
        } catch {
            // Ignore restoration errors
        }
    }

    private func pruneEWMAIfNeeded(now: Date = Date()) {
        // Drop entries inactive beyond TTL
        if !hostLastSeen.isEmpty {
            for (h, ts) in hostLastSeen {
                if now.timeIntervalSince(ts) > ewmaInactivityTTL {
                    hostLastSeen.removeValue(forKey: h)
                    hostLatencyEWMA.removeValue(forKey: h)
                }
            }
        }
        // Enforce max size by evicting oldest last-seen first
        if hostLastSeen.count > ewmaMaxHosts {
            let over = hostLastSeen.count - ewmaMaxHosts
            let sorted = hostLastSeen.sorted { $0.value < $1.value }
            for i in 0..<min(over, sorted.count) {
                let h = sorted[i].key
                hostLastSeen.removeValue(forKey: h)
                hostLatencyEWMA.removeValue(forKey: h)
            }
        }
    }

    private func ewmaEstimate(for host: String) -> TimeInterval {
        let now = Date()
        if let ts = hostLastSeen[host], now.timeIntervalSince(ts) <= ewmaInactivityTTL, let v = hostLatencyEWMA[host] {
            return v
        }
        return cellularFastTimeout
    }

    private func updateEWMA(for host: String, sample seconds: TimeInterval) {
        guard !host.isEmpty, seconds.isFinite, seconds > 0 else { return }
        let now = Date()
        // Keep the table healthy before insert/update
        pruneEWMAIfNeeded(now: now)
        let prev = hostLatencyEWMA[host] ?? cellularFastTimeout
        let next = (ewmaAlpha * seconds) + ((1.0 - ewmaAlpha) * prev)
        hostLatencyEWMA[host] = min(max(next, minFirstAttemptCellularTimeout), maxFirstAttemptCellularTimeout)
        hostLastSeen[host] = now
        // If we exceeded the cap due to a new host, prune again
        if hostLastSeen.count > ewmaMaxHosts {
            pruneEWMAIfNeeded(now: now)
        }
    }

    // Apply a coherent Now Playing bundle in a single assignment to avoid partial state
    private func applyNowPlaying(_ build: (inout [String: Any]) -> Void) {
        var snapshot = info
        build(&snapshot)
        info = snapshot
        center.nowPlayingInfo = snapshot
    }

    private func startPathMonitorIfNeeded() {
        // Serialize start using the pathMonitorQueue to avoid a window where the monitor was cancelled but flags aren't updated yet.
        var shouldStart = false
        pathMonitorQueue.sync {
            if !self.pathMonitorActiveFlag {
                self.pathMonitorActiveFlag = true
                shouldStart = true
            }
        }
        if shouldStart {
            let monitor = NWPathMonitor()
            self.pathMonitor = monitor

            self.isCellular = true
            self.hasPathUpdate = false

            monitor.pathUpdateHandler = { [weak self] path in
                let onCell = path.isExpensive
                Task { @MainActor [weak self] in
                    self?.isCellular = onCell
                    self?.hasPathUpdate = true
                }
            }
            monitor.start(queue: pathMonitorQueue)
            pathMonitorStarted = true
        }
        // Reset idle timer when activity occurs
        schedulePathMonitorStop()
    }

    private func schedulePathMonitorStop() {
        pathMonitorQueue.async { [weak self] in
            guard let self = self else { return }
            // Cancel any existing timer on the pathMonitorQueue
            if let t = self.pathMonitorIdleTimer {
                t.cancel()
                self.pathMonitorIdleTimer = nil
            }
            // Create a queue-backed timer to avoid run-loop mode deferrals
            let timer = DispatchSource.makeTimerSource(queue: self.pathMonitorQueue)
            timer.schedule(deadline: .now() + self.pathMonitorIdleGrace, repeating: DispatchTimeInterval.never)
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                // Stop monitor and tear down timer on the pathMonitorQueue
                self.pathMonitorActiveFlag = false
                if let monitor = self.pathMonitor {
                    monitor.cancel()
                    self.pathMonitor = nil
                }
                // Clear timer reference
                if let t2 = self.pathMonitorIdleTimer { t2.cancel() }
                self.pathMonitorIdleTimer = nil
                // Update flags on MainActor to keep actor isolation
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.pathMonitorStarted = false
                    self.hasPathUpdate = false
                }
            }
            self.pathMonitorIdleTimer = timer
            timer.resume()
        }
    }

    private func handleMemoryPressure() {
        // Signal current artwork provider to purge bucket images; keep master only by default
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMemoryWarningTime > memoryWarningWindow { consecutiveMemoryWarnings = 0 }
        lastMemoryWarningTime = now
        consecutiveMemoryWarnings += 1

        let wallNow = Date()
        self.bucketRehydrateUntil = wallNow.addingTimeInterval(self.bucketRehydrateCooldown)

        if let control = currentArtworkControl {
            control.purge = true
            control.buckets = nil
            let paused = (lastPublishedRate ?? 1.0) == 0.0
            if (isBackgrounded || paused) && consecutiveMemoryWarnings >= 2 {
                self.ensurePlaceholderAvailable(on: control)
                control.dropMaster = true
            }
        }
        self.lastPlaceholderImage = nil
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

    // Render a tiny placeholder with subtle gradient and inner shadow for contrast/depth
    private func renderPlaceholderImage(pointSize: CGSize, baseColor: UIColor, scale: CGFloat, style: UIUserInterfaceStyle) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(1, scale)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pointSize, format: format)
        let img = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: pointSize)
            // Fill base color
            baseColor.setFill()
            ctx.fill(rect)

            // Subtle vertical gradient for depth
            let cgCtx = ctx.cgContext
            let colors: [CGColor]
            if style == .dark {
                colors = [UIColor(white: 1.0, alpha: 0.06).cgColor,
                          UIColor(white: 0.0, alpha: 0.12).cgColor]
            } else {
                colors = [UIColor(white: 1.0, alpha: 0.12).cgColor,
                          UIColor(white: 0.0, alpha: 0.08).cgColor]
            }
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0]) {
                cgCtx.saveGState()
                cgCtx.addRect(rect)
                cgCtx.clip()
                let start = CGPoint(x: rect.midX, y: rect.minY)
                let end = CGPoint(x: rect.midX, y: rect.maxY)
                cgCtx.drawLinearGradient(gradient, start: start, end: end, options: [])
                cgCtx.restoreGState()
            }

            // Inner shadow/border to improve edge contrast
            let inset: CGFloat = 0.5 / format.scale
            let innerRect = rect.insetBy(dx: inset, dy: inset)
            let path = UIBezierPath(roundedRect: innerRect, cornerRadius: min(pointSize.width, pointSize.height) * 0.08)
            path.lineWidth = max(0.5, 1.0 / format.scale)
            let strokeColor: UIColor = (style == .dark) ? UIColor(white: 1.0, alpha: 0.10) : UIColor(white: 0.0, alpha: 0.15)
            strokeColor.setStroke()
            path.stroke()
        }
        return img
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

        // Adjust base color slightly for better contrast in dark/light modes
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        let baseColor: UIColor
        if style == .dark {
            // Slightly higher brightness/saturation in dark mode for contrast
            baseColor = color.withAlphaComponent(1.0)
        } else {
            baseColor = color.withAlphaComponent(1.0)
        }
        let img = renderPlaceholderImage(pointSize: pointSize, baseColor: baseColor, scale: scale, style: style)
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
                let style = UIScreen.main.traitCollection.userInterfaceStyle
                // Choose a neutral base with sufficient contrast in both modes
                let neutralBase: UIColor = (style == .dark) ? UIColor(hue: 0.6, saturation: 0.18, brightness: 0.32, alpha: 1.0)
                                                            : UIColor(hue: 0.6, saturation: 0.10, brightness: 0.90, alpha: 1.0)
                let img = renderPlaceholderImage(pointSize: size, baseColor: neutralBase, scale: UIScreen.main.scale, style: style)
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
        if let allowedRedirectHosts {
            let ascii = Set(allowedRedirectHosts.compactMap { NowPlayingService.normalizeHostASCII($0) })
            self.allowedRedirectHosts = ascii.isEmpty ? nil : ascii
        } else {
            self.allowedRedirectHosts = nil
        }
        if let allowedRedirectOrgDomains {
            let ascii = Set(allowedRedirectOrgDomains.compactMap { NowPlayingService.normalizeHostASCII($0) })
            self.allowedRedirectOrgDomains = ascii.isEmpty ? nil : ascii
        } else {
            self.allowedRedirectOrgDomains = nil
        }
        self.bucketStrategy = bucketStrategy
        self.cellularTimeoutOverrideHosts = cellularTimeoutOverrideHosts
        if let decodeMaxPixelSize, decodeMaxPixelSize > 0 {
            self.artworkMasterMaxPixelSize = decodeMaxPixelSize
        }
        self.runtimeSupportedMIMEs = NowPlayingService.detectRuntimeSupportedMIMEs()

        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .useProtocolCachePolicy
        // Create a dedicated cache sized for artwork needs; avoid URLCache.shared
        let memCap = 8 * 1024 * 1024 // 8 MB
        let diskCap = 64 * 1024 * 1024 // 64 MB
        let privateCache = URLCache(memoryCapacity: memCap, diskCapacity: diskCap, directory: nil)
        cfg.urlCache = privateCache
        #if DEBUG
        assert(cfg.requestCachePolicy != .reloadIgnoringLocalAndRemoteCacheData, "Prod sessions should not be ephemeral when caching is required")
        #else
        if cfg.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData {
            cfg.requestCachePolicy = .useProtocolCachePolicy
        }
        #endif

        self.urlSession = URLSession(configuration: cfg, delegate: nil, delegateQueue: nil)
        self.artworkURLCache = privateCache
        #if DEBUG
        assert(self.urlSession.configuration.urlCache === self.artworkURLCache, "URLSession must use the private artwork URLCache for conditional GET validators.")
        #endif

        self.restoreEWMA()

        memoryWarningObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleMemoryPressure()
        }
        bgObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isBackgrounded = true
            self?.persistEWMA()
        }
        fgObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isBackgrounded = false
            self?.consecutiveMemoryWarnings = 0
        }
        raObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.persistEWMA()
        }
        termObserver = NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.persistEWMA()
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

        let hasDefault = info[MPNowPlayingInfoPropertyDefaultPlaybackRate] != nil

        // Publish progress update now as a coherent bundle
        lastProgressUptime = nowUptime
        applyNowPlaying {
            $0[MPNowPlayingInfoPropertyElapsedPlaybackTime] = clampedElapsed
            $0[MPNowPlayingInfoPropertyPlaybackRate] = rate
            if rate > 0 {
                if !hasDefault {
                    $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                }
            } else {
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
                    $0[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                }
            } else {
                $0.removeValue(forKey: MPNowPlayingInfoPropertyDefaultPlaybackRate)
            }
        }

        let isLive = safeDuration <= 0
        if lastIsLive != isLive {
            lastIsLive = isLive
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

    /// Set or clear the currently published artwork.
    /// - Parameter urlString: HTTPS URL string to fetch artwork from. Pass `nil` to clear artwork.
    /// - Important: Passing `nil` is treated as an alias for `clearArtwork()` and will cancel any in-flight
    ///   artwork work, advance the generation token, and remove artwork from Now Playing coherently.
    public func setArtwork(from urlString: String?) {
        if urlString == nil {
            clearArtwork()
            return
        }

        // Cancel any in-flight artwork fetch/decode
        artworkTask?.cancel()
        artworkTask = nil

        guard let s = urlString, let url = URL(string: s) else { return }
        // Enforce HTTPS only
        guard url.scheme?.lowercased() == "https" else { return }

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
        let originalHost = NowPlayingService.normalizeHostASCII(url.host ?? "")
        let redirectAllowlist = self.allowedRedirectHosts.map { Array($0) }
        let orgDomains = self.allowedRedirectOrgDomains.map { Array($0) }
        let screenScale = UIScreen.main.scale
        let isCompactLayout: Bool = {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) {
                let tc = scene.traitCollection
                return tc.horizontalSizeClass == .compact || tc.verticalSizeClass == .compact
            }
            let tc = UIScreen.main.traitCollection
            return tc.horizontalSizeClass == .compact || tc.verticalSizeClass == .compact
        }()
        let decodeCap = self.artworkMasterMaxPixelSize
        let allowedMimes = self.allowedImageMIMETypes
        let maxBytes = self.artworkMaxBytes
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
                    let appliedTimeout: TimeInterval
                    if onCellular {
                        let host = originalHost
                        let overrideFast = (host != nil) && (timeoutOverrideHosts?.contains(host!) ?? false)
                        if overrideFast {
                            appliedTimeout = wifiTimeout
                        } else {
                            if attempt == 0 {
                                let base = await MainActor.run { () -> TimeInterval in
                                    let h = host ?? ""
                                    let est = (!h.isEmpty) ? self.ewmaEstimate(for: h) : self.cellularFastTimeout
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
                    let validation = NowPlayingService.isFinalURLAllowed(finalURL: http.url, originalHostASCII: originalHost, redirectAllowlist: redirectAllowlist, orgDomains: orgDomains)
                    if !validation.allowed { return }
                    let finalHostASCII = validation.finalHostASCII

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
                            else {
                                // Missing Content-Type on cached 304 entry; bail to avoid decode churn
                                return
                            }
                            data = cached.data
                            let fetchDuration = ProcessInfo.processInfo.systemUptime - fetchStart

                            if let h = finalHostASCII ?? originalHost {
                                await MainActor.run { self.updateEWMA(for: h, sample: fetchDuration) }
                            }

                            fetchSucceeded = true
                        } else {
                            var fallbackReq = req
                            fallbackReq.cachePolicy = .reloadIgnoringLocalCacheData
                            fallbackReq.setValue(nil, forHTTPHeaderField: "If-None-Match")
                            fallbackReq.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
                            fallbackReq.setValue("image/*", forHTTPHeaderField: "Accept") // inserted as per instructions

                            let session2 = self.urlSession
                            #if DEBUG
                            assert(session2.configuration.urlCache != nil, "URLSession must have a URLCache for conditional GET validators.")
                            #endif

                            var finalHostASCIIForFallback: String? = nil

                            let (bytes2, resp2) = try await session2.bytes(for: fallbackReq, delegate: nil)

                            if let http2 = resp2 as? HTTPURLResponse {
                                let validation2 = NowPlayingService.isFinalURLAllowed(finalURL: http2.url, originalHostASCII: originalHost, redirectAllowlist: redirectAllowlist, orgDomains: orgDomains)
                                finalHostASCIIForFallback = validation2.finalHostASCII
                                #if DEBUG
                                if !validation2.allowed { assertionFailure("Redirect/HTTPS policy must be respected on 304 fallback") }
                                #endif
                                if !validation2.allowed { return }
                                if let contentTypeHeader2 = http2.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                                    let mimeType2 = contentTypeHeader2.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? contentTypeHeader2
                                    let allowedMimesRuntime2 = allowedMimes.intersection(runtimeSupportedMimes)
                                    let isSuppressed2 = await MainActor.run { () -> Bool in
                                        if let until = self.suppressedMIMEUntil[mimeType2], until > Date() {
                                            return true
                                        } else if let until = self.suppressedMIMEUntil[mimeType2], until <= Date() {
                                            self.suppressedMIMEUntil.removeValue(forKey: mimeType2)
                                            self.enforceMimeSuppressionCap()
                                            return false
                                        }
                                        return false
                                    }
                                    guard allowedMimesRuntime2.contains(mimeType2) else { return }
                                    if isSuppressed2 { return }
                                }
                                else {
                                    // Missing Content-Type on 304 fallback response; bail
                                    return
                                }
                                if let lenStr2 = http2.value(forHTTPHeaderField: "Content-Length"), let len2 = Int(lenStr2), len2 > maxBytes {
                                    return
                                }
                            }

                            data.removeAll(keepingCapacity: false)
                            for try await chunk in bytes2 {
                                if Task.isCancelled { return }
                                data.append(chunk)
                                if data.count > maxBytes {
                                    return
                                }
                            }
                            let fetchDuration2 = ProcessInfo.processInfo.systemUptime - fetchStart
                            if let h = finalHostASCIIForFallback ?? originalHost {
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
                    if let h = finalHostASCII ?? originalHost {
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
                kCGImageSourceCreateThumbnailWithTransform: true,
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
                // Round target pixels to nearest integer >= 1 for stable sampling
                let targetW = max(1, Int(round(size.width)))
                let targetH = max(1, Int(round(size.height)))
                // Skip downscale if target equals master size
                if targetW == image.width && targetH == image.height { return nil }
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bytesPerPixel = 4
                let bitsPerComponent = 8
                let bytesPerRow = targetW * bytesPerPixel
                guard let ctx = CGContext(data: nil,
                                          width: targetW,
                                          height: targetH,
                                          bitsPerComponent: bitsPerComponent,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(origin: .zero, size: CGSize(width: targetW, height: targetH)))
                return ctx.makeImage()
            }

            let strategy = await MainActor.run { self.bucketStrategy }
            let masterMaxPixels = CGFloat(max(masterCG.width, masterCG.height))
            let masterMaxPoints = masterMaxPixels / screenScale
            var cgBucketImages: [Int: CGImage] = [:]

            let effectiveStrategy: ArtworkBucketStrategy = (masterMaxPoints < 480) ? .one : strategy

            var bucketPoints: [Int]
            switch effectiveStrategy {
            case .one:  bucketPoints = [NowPlayingService.bucketThresholds[1]]
            case .two:  bucketPoints = [NowPlayingService.bucketThresholds[0], NowPlayingService.bucketThresholds[1]]
            case .three: bucketPoints = NowPlayingService.bucketThresholds
            }

            let allow1024 = (masterMaxPoints >= 900) && (!isCompactLayout)
            if !allow1024 {
                bucketPoints.removeAll { $0 == NowPlayingService.bucketThresholds.last }
            }

            if let smallest = bucketPoints.min(), masterMaxPoints < CGFloat(smallest) {
                // Do not generate buckets; provider will use master/placeholder
            } else {
                for bp in bucketPoints {
                    let bpPoints = CGFloat(bp)
                    if bpPoints > masterMaxPoints { continue }
                    let scale = min(bpPoints / max(boundsSize.width, boundsSize.height), 1.0)
                    let targetPixels = CGSize(width: boundsSize.width * scale * screenScale,
                                              height: boundsSize.height * scale * screenScale)
                    if let scaled = cgImageScaled(masterCG, toPixelSize: targetPixels) {
                        cgBucketImages[bp] = scaled
                    }
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

                #if DEBUG
                precondition((control.buckets?.count ?? 0) <= 3, "Artwork cache should be bounded to <= 3 buckets")
                #endif

                let providerFallbackImage = control.placeholder ?? control.master ?? self.tinyFallbackImage

                let artwork = MPMediaItemArtwork(boundsSize: boundsSize) { requested in
                    #if DEBUG
                    precondition((control.buckets?.count ?? 0) <= 3, "Artwork cache should be bounded to <= 3 buckets")
                    #endif

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

        currentArtworkControl = nil

        schedulePathMonitorStop()
    }

    deinit {
        pathMonitorQueue.async { [weak self] in
            guard let self = self else { return }
            self.pathMonitor?.cancel()
            self.pathMonitor = nil
            if let t = self.pathMonitorIdleTimer { t.cancel() }
            self.pathMonitorIdleTimer = nil
        }
        artworkTask?.cancel()
        if let token = memoryWarningObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = bgObserver { NotificationCenter.default.removeObserver(token) }
        if let token = fgObserver { NotificationCenter.default.removeObserver(token) }
        if let token = raObserver { NotificationCenter.default.removeObserver(token) }
        if let token = termObserver { NotificationCenter.default.removeObserver(token) }
    }
}

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
        let bias: CGFloat = NowPlayingService.bucketBias
        let thresholds = NowPlayingService.bucketThresholds
        let b: Int
        if maxDim <= CGFloat(thresholds[0]) * bias { b = thresholds[0] }
        else if maxDim <= CGFloat(thresholds[1]) * bias { b = thresholds[1] }
        else { b = thresholds[2] }
        if let img = buckets?[b] { return img }
        return master
    }
}

