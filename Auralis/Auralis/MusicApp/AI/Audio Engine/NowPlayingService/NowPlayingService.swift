import Foundation
import MediaPlayer
import UIKit
import CoreGraphics
import ImageIO
import Network

@MainActor
public final class NowPlayingService {
    // MARK: - Network Path Monitoring
    var pathMonitor: NWPathMonitor? = nil
    var pathMonitorStarted: Bool = false
    let pathMonitorQueue = DispatchQueue(label: "NowPlayingService.PathMonitor", qos: .utility)
    var pathMonitorIdleTimer: DispatchSourceTimer? = nil
    let pathMonitorIdleGrace: TimeInterval = 30 // seconds of idle before stopping monitor
    // Queue-serialized active flag to avoid start/stop races
    var pathMonitorActiveFlag: Bool = false

    // Path state captured from NWPathMonitor
    var isCellular: Bool = false
    var hasPathUpdate: Bool = false

    // MARK: - App Lifecycle / Memory Pressure
    var memoryWarningObserver: NSObjectProtocol? = nil
    var bgObserver: NSObjectProtocol? = nil
    var fgObserver: NSObjectProtocol? = nil
    var raObserver: NSObjectProtocol? = nil
    var termObserver: NSObjectProtocol? = nil
    var isBackgrounded: Bool = false

    var lastMemoryWarningTime: TimeInterval = 0
    let memoryWarningWindow: TimeInterval = 60 // seconds to group warnings
    var consecutiveMemoryWarnings: Int = 0

    // MARK: - Artwork / Placeholder cache
    var lastPlaceholderImage: UIImage? = nil

    // MARK: - MIME Suppression / Decode failure tracking
    var suppressedMIMEUntil: [String: Date] = [:]
    var mimeDecodeFailureCounts: [String: Int] = [:]
    let mimeSuppressionTTL: TimeInterval = 3600 // 1 hour suppression for problematic MIME types
    let mimeSuppressionCap: Int = 64 // cap number of suppressed MIME entries
    let decodeSuppressionThreshold: Int = 3 // consecutive decode failures before suppression

    // MARK: - Cellular timeout policy
    let cellularFastTimeout: TimeInterval = 1.5 // default first-attempt timeout on cellular when no EWMA
    let cellularTimeoutOverrideHosts: Set<String>?

    // MARK: - Bucket rehydration policy (after memory pressure)
    var bucketRehydrateUntil: Date? = nil
    let bucketRehydrateCooldown: TimeInterval = 60 // seconds to defer bucket rehydration

    nonisolated static let bucketThresholds: [Int] = [256, 512, 1024]
    nonisolated static let bucketBias: CGFloat = 1.10

    var center: NowPlayingCentering
    var info: [String: Any] = [:]
    var lastProgressUptime: TimeInterval?
    let cadence: TimeInterval
    /// Micro-seek bypass threshold (in seconds).
    ///
    /// Rationale:
    /// - We throttle progress updates to the system using `cadence` to conserve battery and avoid noisy UI churn.
    /// - However, small user-initiated seeks (typically ±1–2 seconds) should reflect immediately on system surfaces
    ///   like Control Center and the Lock Screen so the scrubber jumps without delay.
    /// - Setting this to 1.0s means any elapsed-time change of ≥ 1.0s bypasses cadence and publishes immediately,
    ///   while continuous playback (small deltas) remains throttled by `cadence`.
    let progressSignificantDelta: TimeInterval = 1.0
    var artworkGeneration: Int = 0
    var artworkTask: Task<Void, Never>?

    public enum ArtworkBucketStrategy { case one, two, three }
    var bucketStrategy: ArtworkBucketStrategy
    
    var bucketStrategyCooldownUntil: Date? = nil
    let bucketStrategyCooldown: TimeInterval = 300 // 5 minutes

    let urlSession: URLSession
    let artworkURLCache: URLCache

    var currentArtworkControl: ArtworkCacheControl?

    var lastPublishedElapsed: TimeInterval?
    var lastPublishedRate: Double?
    var lastIsLive: Bool? = nil

    let artworkRequestTimeout: TimeInterval = 5
    let artworkMaxBytes: Int = 10 * 1024 * 1024 // 10 MB cap
    let allowedImageMIMETypes: Set<String> = ["image/jpeg", "image/jpg", "image/pjpeg", "image/png", "image/webp", "image/heic", "image/heif"]
    var artworkMasterMaxPixelSize: CGFloat = 1024
    let allowedRedirectHosts: Set<String>?
    let allowedRedirectOrgDomains: Set<String>?

    let runtimeSupportedMIMEs: Set<String>
    var hostLatencyEWMA: [String: TimeInterval] = [:]
    let ewmaAlpha: Double = 0.3
    let minFirstAttemptCellularTimeout: TimeInterval = 1.0
    let maxFirstAttemptCellularTimeout: TimeInterval = 5.0

    var hostLastSeen: [String: Date] = [:]
    let ewmaInactivityTTL: TimeInterval = 1800 // 30 minutes
    let ewmaMaxHosts: Int = 256

    let ewmaPersistKey = "NowPlayingService.EWMA.v1"

    func applyNowPlaying(_ build: (inout [String: Any]) -> Void) {
        var snapshot = info
        build(&snapshot)
        info = snapshot
        center.nowPlayingInfo = snapshot
    }

    lazy var tinyFallbackImage: UIImage = {
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
    
    func bucketCount(_ s: ArtworkBucketStrategy) -> Int {
        switch s { case .one: return 1; case .two: return 2; case .three: return 3 }
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
