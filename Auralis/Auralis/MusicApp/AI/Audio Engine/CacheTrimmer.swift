import Foundation
import Darwin

/// Recency policy for cache trimming date selection.
public enum CacheRecencyPolicy: Sendable {
    case accessDate
    case modificationDate
}

/// Severity levels for a failed deletion.
public enum CacheTrimFailureSeverity: String, Sendable {
    case notFound
    case permissionDenied
    case other
}

/// Sendable diagnostics for a failed deletion.
public struct CacheTrimFailure: Sendable {
    public let url: URL
    public let domain: String
    public let code: Int
    public let message: String
    public let severity: CacheTrimFailureSeverity

    public init(url: URL, domain: String, code: Int, message: String, severity: CacheTrimFailureSeverity = .other) {
        self.url = url
        self.domain = domain
        self.code = code
        self.message = message
        self.severity = severity
    }
}

/// Result metrics for a trimming run.
public struct CacheTrimResult: Sendable {
    public let bytesFreed: Int64
    public let filesDeleted: Int
    public let failures: [CacheTrimFailure]
    public let lockAcquired: Bool
    public let recencyPolicy: CacheRecencyPolicy
    public let lockAttempts: Int
    public let lockWaitNanos: UInt64

    public init(
        bytesFreed: Int64,
        filesDeleted: Int,
        failures: [CacheTrimFailure],
        lockAcquired: Bool = true,
        recencyPolicy: CacheRecencyPolicy = .modificationDate,
        lockAttempts: Int = 0,
        lockWaitNanos: UInt64 = 0
    ) {
        self.bytesFreed = bytesFreed
        self.filesDeleted = filesDeleted
        self.failures = failures
        self.lockAcquired = lockAcquired
        self.recencyPolicy = recencyPolicy
        self.lockAttempts = lockAttempts
        self.lockWaitNanos = lockWaitNanos
    }
}

/// A simple advisory file lock to coordinate trimming across processes.
/// Writers may also opt to acquire a shared or exclusive lock on the same lock file to coordinate.
private final class FileLock {
    private let lockURL: URL
    private var fd: Int32 = -1

    init(directory: URL, name: String = ".cache_trimmer.lock") {
        self.lockURL = directory.appendingPathComponent(name, isDirectory: false)
    }

    @inline(__always)
    private func monotonicNowNanos() -> UInt64 {
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS)
        if #available(iOS 10.0, macOS 10.12, tvOS 10.0, watchOS 3.0, *) {
            return UInt64(clock_gettime_nsec_np(CLOCK_MONOTONIC))
        } else {
            return DispatchTime.now().uptimeNanoseconds
        }
        #else
        return DispatchTime.now().uptimeNanoseconds
        #endif
    }

    @inline(__always)
    private func timespecFrom(interval: TimeInterval) -> timespec {
        var interval = interval
        if interval < 0 { interval = 0 }
        if interval > 1 { interval = 1 }
        let sec = time_t(floor(interval))
        let nsec = Int((interval - Double(sec)) * 1_000_000_000)
        return timespec(tv_sec: sec, tv_nsec: nsec)
    }

#if DEBUG
    @available(*, deprecated, message: "Use non-blocking tryLockOnce with async retry; blocking lock may reduce concurrency.")
    func lock(timeout: TimeInterval = 1.0, retryInterval: TimeInterval = 0.05) throws {
        // Ensure the lock file exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: lockURL.path) {
            _ = fm.createFile(atPath: lockURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        }
        fd = open(lockURL.path, O_RDONLY)
        if fd == -1 { throw POSIXError(.EIO) }

        let safeTimeout = max(0, min(timeout, 60))
        let safeRetry = min(max(0, retryInterval), 1.0)
        let deadline = monotonicNowNanos() + UInt64(safeTimeout * 1_000_000_000)

        while true {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return // acquired
            }
            let currentErrno = errno
            if currentErrno == EWOULDBLOCK {
                let now = monotonicNowNanos()
                if now >= deadline {
                    _ = close(fd)
                    fd = -1
                    throw POSIXError(.EWOULDBLOCK)
                }
                var ts = timespecFrom(interval: safeRetry)
                nanosleep(&ts, nil)
                continue
            } else {
                _ = close(fd)
                fd = -1
                throw POSIXError(POSIXErrorCode(rawValue: Int32(currentErrno)) ?? .EIO)
            }
        }
    }
#else
    @available(*, unavailable, message: "Unavailable in production; use tryLockOnce with async retry.")
    func lock(timeout: TimeInterval = 1.0, retryInterval: TimeInterval = 0.05) throws {
        fatalError("FileLock.lock is unavailable in production builds.")
    }
#endif

    func unlock() {
        if fd != -1 {
            _ = flock(fd, LOCK_UN)
            _ = close(fd)
            fd = -1
        }
    }

    func tryLockOnce() throws -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: lockURL.path) {
            _ = fm.createFile(atPath: lockURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        }
        if fd == -1 {
            fd = open(lockURL.path, O_RDONLY)
            if fd == -1 { throw POSIXError(.EIO) }
        }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            return true
        }
        let currentErrno = errno
        if currentErrno == EWOULDBLOCK {
            return false
        } else {
            throw POSIXError(POSIXErrorCode(rawValue: Int32(currentErrno)) ?? .EIO)
        }
    }

    deinit {
        unlock()
    }
}

public struct CacheTrimmer {
    public let metadataExtension: String

    private let accessSampleLimit: Int
    private let accessDateThreshold: Double

    // Dedicated serial queue to offload IO work and prevent main-thread stalls.
    private let ioQueue = DispatchQueue(label: "CacheTrimmer.IO", qos: .utility)

    public init(metadataExtension: String) {
        self.metadataExtension = metadataExtension
        self.accessSampleLimit = 32
        self.accessDateThreshold = 0.5
    }

    public init(metadataExtension: String, accessSampleLimit: Int = 32, accessDateThreshold: Double = 0.5) {
        self.metadataExtension = metadataExtension
        // ioQueue is let constant initialized at declaration, no need to reinitialize here.
        self.accessSampleLimit = max(1, accessSampleLimit)
        self.accessDateThreshold = min(max(0.0, accessDateThreshold), 1.0)
    }

    // MARK: - Preferred async APIs

    /// Trims the cache down to at most `maxBytes`. Runs off the main thread.
    /// - Note: The `progress` closure (if provided) is invoked on the internal ioQueue; dispatch to the main actor before updating UI.
    /// - Warning: If deliverOnMain is false, progress runs on the internal ioQueue; avoid heavy work or hop to the main actor as needed.
    /// - Note: Use the 'seconds' parameter for time-based pacing; when provided, progress is emitted at most once per interval.
    /// - Parameter deletions: Count-based pacing for progress callbacks (default 20).
    /// - Parameter seconds: Optional time-based pacing interval for progress callbacks. If provided, progress is emitted at most once per interval.
    /// - Parameter bytes: Optional bytes-based pacing threshold for progress callbacks.
    /// - Parameter progressEx: Extended progress callback that also includes total files and total bytes.
    /// - Parameter progressETA: Extended progress callback including remaining bytes and ETA (seconds), signature: (filesDeleted, bytesFreed, totalFiles, totalBytes, remainingBytes, etaSeconds)
    /// - Parameter strictCap: When true and trimming by maxBytes, disables slack and enforces a hard cap.
    /// - Parameter deliverOnMain: When true, progress callbacks are dispatched to the main queue.
    /// - Parameter minMainInterval: Minimum interval between progress callbacks when deliverOnMain is true (default 0.25s).
    /// - Parameter requireLock: When true, aborts and returns early if the coordination lock isn't acquired.
    /// - Note: If the result indicates lockAcquired == false, consider retrying or scheduling a later trim to reduce contention.
    /// - Note: When lock coordination fails (lockAcquired == false), trimming proceeds best-effort without coordination; consider retrying later or informing the user.
    @discardableResult
    public func trim(
        toMaxBytes maxBytes: Int64,
        in cacheDir: URL,
        progress: (@Sendable (Int, Int64) -> Void)? = nil,
        progressEvery deletions: Int = 20,
        progressInterval seconds: TimeInterval? = nil,
        progressEx: (@Sendable (Int, Int64, Int, Int64) -> Void)? = nil,
        progressETA: (@Sendable (Int, Int64, Int, Int64, Int64, TimeInterval) -> Void)? = nil,
        strictCap: Bool = true,
        progressEveryBytes bytes: Int64? = nil,
        deliverOnMain: Bool = true,
        minMainInterval: TimeInterval? = nil,
        requireLock: Bool = false
    ) async -> CacheTrimResult {
        await runTrim(
            mode: .maxBytes(maxBytes),
            in: cacheDir,
            progress: progress,
            deletions: deletions,
            seconds: seconds,
            progressEx: progressEx,
            progressETA: progressETA,
            strictCap: strictCap,
            bytes: bytes,
            deliverOnMain: deliverOnMain,
            minMainInterval: minMainInterval,
            requireLock: requireLock
        )
    }

    @MainActor
    @discardableResult
    public func trim(
        toMaxBytes maxBytes: Int64,
        in cacheDir: URL,
        progress: (@Sendable (Int, Int64) -> Void)? = nil,
        progressEvery deletions: Int = 20,
        progressInterval seconds: TimeInterval? = nil,
        progressEx: (@Sendable (Int, Int64, Int, Int64) -> Void)? = nil,
        progressETA: (@Sendable (Int, Int64, Int, Int64, Int64, TimeInterval) -> Void)? = nil,
        strictCap: Bool = true,
        progressEveryBytes bytes: Int64? = nil,
        minMainInterval: TimeInterval? = nil,
        requireLock: Bool = false
    ) async -> CacheTrimResult {
        await trim(
            toMaxBytes: maxBytes,
            in: cacheDir,
            progress: progress,
            progressEvery: deletions,
            progressInterval: seconds,
            progressEx: progressEx,
            progressETA: progressETA,
            strictCap: strictCap,
            progressEveryBytes: bytes,
            deliverOnMain: true,
            minMainInterval: minMainInterval,
            requireLock: requireLock
        )
    }

    /// Aggressively trims the cache down to `watermark`. Runs off the main thread.
    /// - Note: The `progress` closure (if provided) is invoked on the internal ioQueue; dispatch to the main actor before updating UI.
    /// - Warning: If deliverOnMain is false, progress runs on the internal ioQueue; avoid heavy work or hop to the main actor as needed.
    /// - Note: Use the 'seconds' parameter for time-based pacing; when provided, progress is emitted at most once per interval.
    /// - Parameter deletions: Count-based pacing for progress callbacks (default 20).
    /// - Parameter seconds: Optional time-based pacing interval for progress callbacks. If provided, progress is emitted at most once per interval.
    /// - Parameter bytes: Optional bytes-based pacing threshold for progress callbacks.
    /// - Parameter progressEx: Extended progress callback that also includes total files and total bytes.
    /// - Parameter progressETA: Extended progress callback including remaining bytes and ETA (seconds), signature: (filesDeleted, bytesFreed, totalFiles, totalBytes, remainingBytes, etaSeconds)
    /// - Parameter strictCap: When true and trimming by maxBytes, disables slack and enforces a hard cap.
    /// - Parameter deliverOnMain: When true, progress callbacks are dispatched to the main queue.
    /// - Parameter minMainInterval: Minimum interval between progress callbacks when deliverOnMain is true (default 0.25s).
    /// - Parameter requireLock: When true, aborts and returns early if the coordination lock isn't acquired.
    /// - Note: If the result indicates lockAcquired == false, consider retrying or scheduling a later trim to reduce contention.
    /// - Note: When lock coordination fails (lockAcquired == false), trimming proceeds best-effort without coordination; consider retrying later or informing the user.
    @discardableResult
    public func aggressiveTrim(
        toWatermark watermark: Int64,
        in cacheDir: URL,
        progress: (@Sendable (Int, Int64) -> Void)? = nil,
        progressEvery deletions: Int = 20,
        progressInterval seconds: TimeInterval? = nil,
        progressEx: (@Sendable (Int, Int64, Int, Int64) -> Void)? = nil,
        progressETA: (@Sendable (Int, Int64, Int, Int64, Int64, TimeInterval) -> Void)? = nil,
        strictCap: Bool = false,
        progressEveryBytes bytes: Int64? = nil,
        deliverOnMain: Bool = true,
        minMainInterval: TimeInterval? = nil,
        requireLock: Bool = false
    ) async -> CacheTrimResult {
        await runTrim(
            mode: .watermark(watermark),
            in: cacheDir,
            progress: progress,
            deletions: deletions,
            seconds: seconds,
            progressEx: progressEx,
            progressETA: progressETA,
            strictCap: strictCap,
            bytes: bytes,
            deliverOnMain: deliverOnMain,
            minMainInterval: minMainInterval,
            requireLock: requireLock
        )
    }

    @MainActor
    @discardableResult
    public func aggressiveTrim(
        toWatermark watermark: Int64,
        in cacheDir: URL,
        progress: (@Sendable (Int, Int64) -> Void)? = nil,
        progressEvery deletions: Int = 20,
        progressInterval seconds: TimeInterval? = nil,
        progressEx: (@Sendable (Int, Int64, Int, Int64) -> Void)? = nil,
        progressETA: (@Sendable (Int, Int64, Int, Int64, Int64, TimeInterval) -> Void)? = nil,
        strictCap: Bool = false,
        progressEveryBytes bytes: Int64? = nil,
        minMainInterval: TimeInterval? = nil,
        requireLock: Bool = false
    ) async -> CacheTrimResult {
        await aggressiveTrim(
            toWatermark: watermark,
            in: cacheDir,
            progress: progress,
            progressEvery: deletions,
            progressInterval: seconds,
            progressEx: progressEx,
            progressETA: progressETA,
            strictCap: strictCap,
            progressEveryBytes: bytes,
            deliverOnMain: true,
            minMainInterval: minMainInterval,
            requireLock: requireLock
        )
    }

    /// Hysteresis policy: only trims when above `highWatermark`, and trims down to `lowWatermark`.
    /// Returns `.zero` result when no work was needed.
    /// - Note: The `progress` closure (if provided) is invoked on the internal ioQueue; dispatch to the main actor before updating UI.
    /// - Warning: If deliverOnMain is false, progress runs on the internal ioQueue; avoid heavy work or hop to the main actor as needed.
    /// - Note: Use the 'seconds' parameter for time-based pacing; when provided, progress is emitted at most once per interval.
    /// - Parameter deletions: Count-based pacing for progress callbacks (default 20).
    /// - Parameter seconds: Optional time-based pacing interval for progress callbacks. If provided, progress is emitted at most once per interval.
    /// - Parameter bytes: Optional bytes-based pacing threshold for progress callbacks.
    /// - Parameter progressEx: Extended progress callback that also includes total files and total bytes.
    /// - Parameter progressETA: Extended progress callback including remaining bytes and ETA (seconds), signature: (filesDeleted, bytesFreed, totalFiles, totalBytes, remainingBytes, etaSeconds)
    /// - Parameter strictCap: When true and trimming by maxBytes, disables slack and enforces a hard cap.
    /// - Parameter deliverOnMain: When true, progress callbacks are dispatched to the main queue.
    /// - Parameter minMainInterval: Minimum interval between progress callbacks when deliverOnMain is true (default 0.25s).
    /// - Parameter requireLock: When true, aborts and returns early if the coordination lock isn't acquired.
    /// - Note: If the result indicates lockAcquired == false, consider retrying or scheduling a later trim to reduce contention.
    /// - Note: When lock coordination fails (lockAcquired == false), trimming proceeds best-effort without coordination; consider retrying later or informing the user.
    @discardableResult
    public func trimIfNeeded(
        highWatermark: Int64,
        lowWatermark: Int64,
        in cacheDir: URL,
        progress: (@Sendable (Int, Int64) -> Void)? = nil,
        progressEvery deletions: Int = 20,
        progressInterval seconds: TimeInterval? = nil,
        progressEx: (@Sendable (Int, Int64, Int, Int64) -> Void)? = nil,
        progressETA: (@Sendable (Int, Int64, Int, Int64, Int64, TimeInterval) -> Void)? = nil,
        strictCap: Bool = false,
        progressEveryBytes bytes: Int64? = nil,
        deliverOnMain: Bool = true,
        minMainInterval: TimeInterval? = nil,
        requireLock: Bool = false
    ) async -> CacheTrimResult {
        // Validate and normalize hysteresis parameters.
        let hi: Int64
        let lo: Int64
        if lowWatermark > highWatermark {
            hi = lowWatermark
            lo = highWatermark
        } else if lowWatermark == highWatermark {
            // Equal thresholds imply no effective hysteresis; avoid unnecessary work.
            return CacheTrimResult(
                bytesFreed: 0,
                filesDeleted: 0,
                failures: [],
                lockAcquired: false,
                recencyPolicy: .modificationDate,
                lockAttempts: 0,
                lockWaitNanos: 0
            )
        } else {
            hi = highWatermark
            lo = lowWatermark
        }

        return await runTrim(
            mode: .hysteresis(high: hi, low: lo),
            in: cacheDir,
            progress: progress,
            deletions: deletions,
            seconds: seconds,
            progressEx: progressEx,
            progressETA: progressETA,
            strictCap: strictCap,
            bytes: bytes,
            deliverOnMain: deliverOnMain,
            minMainInterval: minMainInterval,
            requireLock: requireLock
        )
    }

    @MainActor
    @discardableResult
    public func trimIfNeeded(
        highWatermark: Int64,
        lowWatermark: Int64,
        in cacheDir: URL,
        progress: (@Sendable (Int, Int64) -> Void)? = nil,
        progressEvery deletions: Int = 20,
        progressInterval seconds: TimeInterval? = nil,
        progressEx: (@Sendable (Int, Int64, Int, Int64) -> Void)? = nil,
        progressETA: (@Sendable (Int, Int64, Int, Int64, Int64, TimeInterval) -> Void)? = nil,
        strictCap: Bool = false,
        progressEveryBytes bytes: Int64? = nil,
        minMainInterval: TimeInterval? = nil,
        requireLock: Bool = false
    ) async -> CacheTrimResult {
        await trimIfNeeded(
            highWatermark: highWatermark,
            lowWatermark: lowWatermark,
            in: cacheDir,
            progress: progress,
            progressEvery: deletions,
            progressInterval: seconds,
            progressEx: progressEx,
            progressETA: progressETA,
            strictCap: strictCap,
            progressEveryBytes: bytes,
            deliverOnMain: true,
            minMainInterval: minMainInterval,
            requireLock: requireLock
        )
    }

    // MARK: - Legacy sync APIs (offloaded)

    /// Deprecated: Offloads work to a background task and returns immediately.
    /// - Important: Cancellation from the caller is only checked before launching the background task.
    ///   After this method returns, cancellation will NOT propagate to the work. Prefer async variants.
    @available(*, deprecated, message: "Use async variants to await completion and receive telemetry.")
    public func trim(toMaxBytes maxBytes: Int64, in cacheDir: URL) {
        let priority = Task.currentPriority
        if Task.isCancelled { return }
        Task(priority: priority) {
            _ = await self.runTrim(mode: .maxBytes(maxBytes), in: cacheDir, progress: nil, deletions: 20, seconds: nil, progressEx: nil, strictCap: false, bytes: nil, deliverOnMain: false)
        }
    }

    /// Deprecated: Offloads work to a background task and returns immediately.
    /// - Important: Cancellation from the caller is only checked before launching the background task.
    ///   After this method returns, cancellation will NOT propagate to the work. Prefer async variants.
    @available(*, deprecated, message: "Use async variants to await completion and receive telemetry.")
    public func aggressiveTrim(toWatermark watermark: Int64, in cacheDir: URL) {
        let priority = Task.currentPriority
        if Task.isCancelled { return }
        Task(priority: priority) {
            _ = await self.runTrim(mode: .watermark(watermark), in: cacheDir, progress: nil, deletions: 20, seconds: nil, progressEx: nil, strictCap: false, bytes: nil, deliverOnMain: false)
        }
    }

    /// Deprecated: Offloads work to a background task and returns immediately.
    /// - Important: Cancellation from the caller is only checked before launching the background task.
    ///   After this method returns, cancellation will NOT propagate to the work. Prefer async variants.
    /// - Parameter cancellationCheck: Optional predicate evaluated before launching work; if it returns true, no work is started.
    @available(*, deprecated, message: "Use async variants to await completion and receive telemetry.")
    public func trim(toMaxBytes maxBytes: Int64, in cacheDir: URL, cancellationCheck: (() -> Bool)?) {
        let priority = Task.currentPriority
        if Task.isCancelled { return }
        if cancellationCheck?() == true { return }
        Task(priority: priority) {
            _ = await self.runTrim(mode: .maxBytes(maxBytes), in: cacheDir, progress: nil, deletions: 20, seconds: nil, progressEx: nil, strictCap: false, bytes: nil, deliverOnMain: false)
        }
    }

    /// Deprecated: Offloads work to a background task and returns immediately.
    /// - Important: Cancellation from the caller is only checked before launching the background task.
    ///   After this method returns, cancellation will NOT propagate to the work. Prefer async variants.
    /// - Parameter cancellationCheck: Optional predicate evaluated before launching work; if it returns true, no work is started.
    @available(*, deprecated, message: "Use async variants to await completion and receive telemetry.")
    public func aggressiveTrim(toWatermark watermark: Int64, in cacheDir: URL, cancellationCheck: (() -> Bool)?) {
        let priority = Task.currentPriority
        if Task.isCancelled { return }
        if cancellationCheck?() == true { return }
        Task(priority: priority) {
            _ = await self.runTrim(mode: .watermark(watermark), in: cacheDir, progress: nil, deletions: 20, seconds: nil, progressEx: nil, strictCap: false, bytes: nil, deliverOnMain: false)
        }
    }

    // MARK: - Internal implementation

    private enum Mode {
        case maxBytes(Int64)
        case watermark(Int64)
        case hysteresis(high: Int64, low: Int64)
    }

    private func runTrim(
        mode: Mode,
        in cacheDir: URL,
        progress: (@Sendable (Int, Int64) -> Void)? = nil,
        deletions: Int = 20,
        seconds: TimeInterval? = nil,
        progressEx: (@Sendable (Int, Int64, Int, Int64) -> Void)? = nil,
        progressETA: (@Sendable (Int, Int64, Int, Int64, Int64, TimeInterval) -> Void)? = nil,
        strictCap: Bool = false,
        bytes: Int64? = nil,
        deliverOnMain: Bool = false,
        minMainInterval: TimeInterval? = nil,
        requireLock: Bool = false
    ) async -> CacheTrimResult {
        if Task.isCancelled {
            return CacheTrimResult(
                bytesFreed: 0, filesDeleted: 0, failures: [], lockAcquired: false,
                recencyPolicy: .modificationDate, lockAttempts: 0, lockWaitNanos: 0
            )
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // If cancelled after entering the handler but before scheduling, bail out.
                if Task.isCancelled {
                    continuation.resume(returning: CacheTrimResult(
                        bytesFreed: 0, filesDeleted: 0, failures: [], lockAcquired: false,
                        recencyPolicy: .modificationDate, lockAttempts: 0, lockWaitNanos: 0
                    ))
                    return
                }
                ioQueue.async {
                    self.acquireLockAsync(in: cacheDir, timeout: 1.0, retryInterval: 0.05) { maybeLock, attempts, waitNanos in
                        self.ioQueue.async {
                            if let lock = maybeLock {
                                defer { lock.unlock() }
                                let result = self._runTrimBody(
                                    mode: mode,
                                    in: cacheDir,
                                    progress: progress,
                                    deletions: deletions,
                                    seconds: seconds,
                                    progressEx: progressEx,
                                    progressETA: progressETA,
                                    strictCap: strictCap,
                                    bytes: bytes,
                                    deliverOnMain: deliverOnMain,
                                    minMainInterval: minMainInterval,
                                    lockAcquired: attempts > 0 && maybeLock != nil,
                                    lockAttempts: attempts,
                                    lockWaitNanos: waitNanos
                                )
                                continuation.resume(returning: result)
                            } else {
                                // Lock acquisition failed or timed out.
                                if requireLock {
                                    let result = CacheTrimResult(
                                        bytesFreed: 0,
                                        filesDeleted: 0,
                                        failures: [],
                                        lockAcquired: false,
                                        recencyPolicy: .modificationDate,
                                        lockAttempts: attempts,
                                        lockWaitNanos: waitNanos
                                    )
                                    continuation.resume(returning: result)
                                } else {
                                    // Proceed best-effort without coordination.
                                    let result = self._runTrimBody(
                                        mode: mode,
                                        in: cacheDir,
                                        progress: progress,
                                        deletions: deletions,
                                        seconds: seconds,
                                        progressEx: progressEx,
                                        progressETA: progressETA,
                                        strictCap: strictCap,
                                        bytes: bytes,
                                        deliverOnMain: deliverOnMain,
                                        minMainInterval: minMainInterval,
                                        lockAcquired: false,
                                        lockAttempts: attempts,
                                        lockWaitNanos: waitNanos
                                    )
                                    continuation.resume(returning: result)
                                }
                            }
                        }
                    }
                }
            }
        } onCancel: {
            // No-op: we cooperatively check cancellation inside the trim loop.
        }
    }

    private func _runTrim(mode: Mode, in cacheDir: URL, failIfUncoordinated: Bool = true) -> CacheTrimResult {
        let lock = FileLock(directory: cacheDir)
        let acquired = (try? lock.tryLockOnce()) ?? false
        let attempts = acquired ? 1 : 0
        let wait: UInt64 = 0
        if acquired {
            defer { lock.unlock() }
            return _runTrimBody(
                mode: mode,
                in: cacheDir,
                progress: nil,
                deletions: 20,
                seconds: nil,
                progressEx: nil,
                progressETA: nil,
                strictCap: false,
                bytes: nil,
                deliverOnMain: false,
                minMainInterval: nil,
                lockAcquired: acquired,
                lockAttempts: attempts,
                lockWaitNanos: wait
            )
        } else {
            if failIfUncoordinated {
                return CacheTrimResult(
                    bytesFreed: 0,
                    filesDeleted: 0,
                    failures: [],
                    lockAcquired: false,
                    recencyPolicy: .modificationDate,
                    lockAttempts: attempts,
                    lockWaitNanos: wait
                )
            }
            return _runTrimBody(
                mode: mode,
                in: cacheDir,
                progress: nil,
                deletions: 20,
                seconds: nil,
                progressEx: nil,
                progressETA: nil,
                strictCap: false,
                bytes: nil,
                deliverOnMain: false,
                minMainInterval: nil,
                lockAcquired: acquired,
                lockAttempts: attempts,
                lockWaitNanos: wait
            )
        }
    }

    private func _runTrimBody(
        mode: Mode,
        in cacheDir: URL,
        progress: (@Sendable (Int, Int64) -> Void)? = nil,
        deletions: Int = 20,
        seconds: TimeInterval? = nil,
        progressEx: (@Sendable (Int, Int64, Int, Int64) -> Void)? = nil,
        progressETA: (@Sendable (Int, Int64, Int, Int64, Int64, TimeInterval) -> Void)? = nil,
        strictCap: Bool = false,
        bytes: Int64? = nil,
        deliverOnMain: Bool = false,
        minMainInterval: TimeInterval? = nil,
        lockAcquired: Bool,
        lockAttempts: Int = 0,
        lockWaitNanos: UInt64 = 0
    ) -> CacheTrimResult {
        var failures: [CacheTrimFailure] = []
        var bytesFreed: Int64 = 0
        var filesDeleted = 0

        let progressBatch = max(1, deletions)
        let timePacing = seconds.map { max(0, $0) }
        let defaultMainMs = 250
        let coalesceMillis: Int = {
            if deliverOnMain {
                if let interval = minMainInterval {
                    return max(0, Int(interval * 1000))
                } else {
                    return defaultMainMs
                }
            } else {
                return 100
            }
        }()
        var lastEmitTime = DispatchTime.now()
        var bytesSinceLastEmit: Int64 = 0
        var pendingProgress = false

        var lastProgressTime = DispatchTime.now()
        var lastProgressBytes: Int64 = 0
        var emaBytesPerSec: Double = 0 // exponential moving average
        let emaAlpha: Double = 0.2

        func emitProgress(force: Bool = false) {
            let now = DispatchTime.now()
            let canEmitTime = now >= lastEmitTime + .milliseconds(coalesceMillis)
            if force || canEmitTime {
                let nowMono = DispatchTime.now()
                let elapsedNs = max(1, nowMono.uptimeNanoseconds &- lastProgressTime.uptimeNanoseconds)
                let deltaBytes = bytesFreed &- lastProgressBytes
                let instBps = Double(deltaBytes) / (Double(elapsedNs) / 1_000_000_000.0)
                if instBps.isFinite && instBps >= 0 {
                    if emaBytesPerSec == 0 { emaBytesPerSec = instBps } else { emaBytesPerSec = emaAlpha * instBps + (1 - emaAlpha) * emaBytesPerSec }
                }
                lastProgressTime = nowMono
                lastProgressBytes = bytesFreed

                let remainingBytes = max<Int64>(0, total - stopThreshold)
                let etaSeconds = (emaBytesPerSec > 0) ? Double(remainingBytes) / emaBytesPerSec : 0

                let call = {
                    progress?(filesDeleted, bytesFreed)
                    progressEx?(filesDeleted, bytesFreed, totalFiles, totalBytes)
                    progressETA?(filesDeleted, bytesFreed, totalFiles, totalBytes, remainingBytes, etaSeconds)
                }
                if deliverOnMain {
                    DispatchQueue.main.async(execute: call)
                } else {
                    call()
                }
                lastEmitTime = now
                bytesSinceLastEmit = 0
                pendingProgress = false
                return
            }
            // Defer until the window elapses; only one pending emit per window.
            pendingProgress = true
        }

        func maybeFlushPending() {
            if pendingProgress {
                let now = DispatchTime.now()
                if now >= lastEmitTime + .milliseconds(coalesceMillis) {
                    emitProgress()
                }
            }
        }

        // First lightweight scan: compute total bytes, total files, and decide recency policy without building the full list.
        let scan = scanTotalAndPolicy(in: cacheDir)
        var total = scan.total
        var policy = scan.policy  // <-- Changed from let to var to allow reassignment below
        let totalFiles = scan.count
        let totalBytes = total

        if Task.isCancelled {
            return CacheTrimResult(
                bytesFreed: 0, filesDeleted: 0, failures: [], lockAcquired: lockAcquired,
                recencyPolicy: policy, lockAttempts: lockAttempts, lockWaitNanos: lockWaitNanos
            )
        }

        // Determine targets based on mode
        let shouldTrim: Bool
        let targetBytes: Int64
        switch mode {
        case .maxBytes(let max):
            shouldTrim = total > max
            targetBytes = max
        case .watermark(let mark):
            shouldTrim = total > mark
            targetBytes = mark
        case .hysteresis(let high, let low):
            shouldTrim = total > high
            targetBytes = low
        }

        guard shouldTrim else {
            return CacheTrimResult(
                bytesFreed: 0, filesDeleted: 0, failures: [], lockAcquired: lockAcquired,
                recencyPolicy: policy, lockAttempts: lockAttempts, lockWaitNanos: lockWaitNanos
            )
        }

        let trimSlackRatio = 0.01
        let slack: Int64
        if strictCap, case .maxBytes = mode {
            slack = 0
        } else {
            slack = Int64(Double(max(0, targetBytes)) * trimSlackRatio)
        }
        let stopThreshold = targetBytes + slack

        // Streamed trimming path: avoids building a full in-memory list. Uses a bounded heap and deletes as we go.
        let streamingCountThreshold = 10_000
        if totalFiles >= streamingCountThreshold {
            struct StreamHeap {
                private var elements: [(url: URL, size: Int64, date: Date)] = []
                private let areSorted: (( (url: URL, size: Int64, date: Date), (url: URL, size: Int64, date: Date) ) -> Bool)
                init(areSorted: @escaping (( (url: URL, size: Int64, date: Date), (url: URL, size: Int64, date: Date) ) -> Bool)) {
                    self.areSorted = areSorted
                }
                mutating func push(_ element: (url: URL, size: Int64, date: Date)) {
                    elements.append(element)
                    siftUp(from: elements.count - 1)

                    if elements.count > 1 {
                        let root = elements[0]
                        let l = 1
                        let r = 2
                        if (l < elements.count && areSorted(elements[l], root)) || (r < elements.count && areSorted(elements[r], root)) {
                            buildHeap()
                        }
                    }
                }
                mutating func pop() -> (url: URL, size: Int64, date: Date)? {
                    guard !elements.isEmpty else { return nil }
                    if elements.count == 1 { return elements.removeLast() }
                    let root = elements[0]
                    elements[0] = elements.removeLast()
                    siftDown(from: 0)

                    if elements.count > 1 {
                        let root = elements[0]
                        let l = 1
                        let r = 2
                        if (l < elements.count && areSorted(elements[l], root)) || (r < elements.count && areSorted(elements[r], root)) {
                            buildHeap()
                        }
                    }

                    return root
                }
                private mutating func siftUp(from index: Int) {
                    var child = index
                    while child > 0 {
                        let parent = (child - 1) / 2
                        if areSorted(elements[child], elements[parent]) {
                            elements.swapAt(child, parent)
                            child = parent
                        } else {
                            break
                        }
                    }
                }
                private mutating func siftDown(from index: Int) {
                    var parent = index
                    let count = elements.count
                    while true {
                        let left = 2 * parent + 1
                        let right = 2 * parent + 2
                        var candidate = parent
                        if left < count && areSorted(elements[left], elements[candidate]) { candidate = left }
                        if right < count && areSorted(elements[right], elements[candidate]) { candidate = right }
                        if candidate == parent { break }
                        elements.swapAt(parent, candidate)
                        parent = candidate
                    }
                }
                private mutating func buildHeap() {
                    for i in stride(from: (elements.count / 2) - 1, through: 0, by: -1) {
                        siftDown(from: i)
                    }
                }
                var isEmpty: Bool { elements.isEmpty }
                var count: Int { elements.count }
            }

            var heap = StreamHeap { a, b in
                if a.date == b.date { return a.size > b.size }
                return a.date < b.date
            }
            let fm = FileManager.default
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .contentAccessDateKey, .fileSizeKey]
            let boundedCapacity = 8192

            if let enumerator = fm.enumerator(at: cacheDir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if Task.isCancelled { break }
                    do {
                        let values = try fileURL.resourceValues(forKeys: keys)
                        if values.isDirectory == true { continue }
                        if isMetadataSidecar(fileURL) { continue }
                        let size = Int64(values.fileSize ?? 0)
                        let access = values.contentAccessDate
                        let mod = values.contentModificationDate
                        let date = (policy == .accessDate ? access : nil) ?? mod ?? .distantPast
                        heap.push((fileURL, size, date))

                        // Keep memory bounded; if heap grows too large, evict oldest immediately.
                        // Only delete from disk when we still need to free bytes (total > stopThreshold).
                        if heap.count > boundedCapacity {
                            if let entry = heap.pop() {
                                if total > stopThreshold {
                                    do {
                                        let sidecarFailure = try delete(entry.url)
                                        bytesFreed += entry.size
                                        filesDeleted += 1
                                        total -= entry.size
                                        if let sf = sidecarFailure { failures.append(sf) }
                                    } catch {
                                        let ns = error as NSError
                                        failures.append(CacheTrimFailure(url: entry.url, domain: ns.domain, code: ns.code, message: ns.localizedDescription))
                                    }
                                    bytesSinceLastEmit += entry.size
                                    if filesDeleted % progressBatch == 0 { emitProgress() }
                                    maybeFlushPending()
                                    if let byteThreshold = bytes, bytesSinceLastEmit >= byteThreshold { emitProgress() }
                                    maybeFlushPending()
                                    if let interval = timePacing, DispatchTime.now() >= lastEmitTime + .milliseconds(Int(interval * 1000)) { emitProgress() }
                                    maybeFlushPending()
                                } else {
                                    // Drop from memory only; keep on-disk contents unchanged.
                                    // No progress or accounting updates.
                                }
                            }
                        }

                        // If we're still above threshold, evict as we go.
                        while total > stopThreshold, let entry = heap.pop() {
                            if Task.isCancelled { break }
                            do {
                                let sidecarFailure = try delete(entry.url)
                                bytesFreed += entry.size
                                filesDeleted += 1
                                total -= entry.size
                                if let sf = sidecarFailure { failures.append(sf) }
                            } catch {
                                let ns = error as NSError
                                failures.append(CacheTrimFailure(url: entry.url, domain: ns.domain, code: ns.code, message: ns.localizedDescription))
                            }
                            bytesSinceLastEmit += entry.size
                            if filesDeleted % progressBatch == 0 { emitProgress() }
                            maybeFlushPending()
                            if let byteThreshold = bytes, bytesSinceLastEmit >= byteThreshold { emitProgress() }
                            maybeFlushPending()
                            if let interval = timePacing, DispatchTime.now() >= lastEmitTime + .milliseconds(Int(interval * 1000)) { emitProgress() }
                            maybeFlushPending()
                        }

                        if total <= stopThreshold { break }
                    } catch { continue }
                }
            }

            // After enumeration, if still above threshold, drain the heap.
            while total > stopThreshold, let entry = heap.pop() {
                if Task.isCancelled { break }
                do {
                    let sidecarFailure = try delete(entry.url)
                    bytesFreed += entry.size
                    filesDeleted += 1
                    total -= entry.size
                    if let sf = sidecarFailure { failures.append(sf) }
                } catch {
                    let ns = error as NSError
                    failures.append(CacheTrimFailure(url: entry.url, domain: ns.domain, code: ns.code, message: ns.localizedDescription))
                }
                bytesSinceLastEmit += entry.size
                if filesDeleted % progressBatch == 0 { emitProgress() }
                maybeFlushPending()
                if let byteThreshold = bytes, bytesSinceLastEmit >= byteThreshold { emitProgress() }
                maybeFlushPending()
                if let interval = timePacing, DispatchTime.now() >= lastEmitTime + .milliseconds(Int(interval * 1000)) { emitProgress() }
                maybeFlushPending()
            }

            if filesDeleted > 0 { emitProgress(force: true) }
            return CacheTrimResult(
                bytesFreed: bytesFreed,
                filesDeleted: filesDeleted,
                failures: failures,
                lockAcquired: lockAcquired,
                recencyPolicy: policy,
                lockAttempts: lockAttempts,
                lockWaitNanos: lockWaitNanos
            )
        }

        // Previous single pass: collect files (size + recency) and compute total simultaneously.
        // Fallback path for smaller caches.

        // We still need to collect files fully here, so call existing helper.
        let collected = collectFilesAndTotal(in: cacheDir)
        var files = collected.files
        total = collected.total
        policy = collected.policy   // <-- insert this line to update policy for telemetry

        // Heuristic: for large file sets and small needed cleanup, use iterative selection to avoid full sort.
        let neededBytes = max(0, total - stopThreshold)
        if files.count > 500 && neededBytes < max(1, total / 20) {
            // Use a min-heap for efficient oldest-first selection with tie-break by larger size.
            struct Heap {
                private var elements: [(url: URL, size: Int64, date: Date)]
                private let areSorted: (( (url: URL, size: Int64, date: Date), (url: URL, size: Int64, date: Date) ) -> Bool)

                init(elements: [(url: URL, size: Int64, date: Date)], areSorted: @escaping (( (url: URL, size: Int64, date: Date), (url: URL, size: Int64, date: Date) ) -> Bool)) {
                    self.elements = elements
                    self.areSorted = areSorted
                    buildHeap()
                }

                mutating func buildHeap() {
                    for i in stride(from: (elements.count / 2) - 1, through: 0, by: -1) {
                        siftDown(from: i)
                    }
                    #if DEBUG
                    if elements.count > 1 {
                        let root = elements[0]
                        let l = 1
                        let r = 2
                        if l < elements.count { assert(!areSorted(elements[l], root), "Heap property violated at left child") }
                        if r < elements.count { assert(!areSorted(elements[r], root), "Heap property violated at right child") }
                    }
                    #endif
                }

                mutating func siftDown(from index: Int) {
                    var parent = index
                    let count = elements.count
                    while true {
                        let left = 2 * parent + 1
                        let right = 2 * parent + 2
                        var candidate = parent
                        if left < count && areSorted(elements[left], elements[candidate]) {
                            candidate = left
                        }
                        if right < count && areSorted(elements[right], elements[candidate]) {
                            candidate = right
                        }
                        if candidate == parent { break }
                        elements.swapAt(parent, candidate)
                        parent = candidate
                    }
                }

                mutating func pop() -> (url: URL, size: Int64, date: Date)? {
                    guard !elements.isEmpty else { return nil }
                    if elements.count == 1 {
                        return elements.removeLast()
                    }
                    let root = elements[0]
                    elements[0] = elements.removeLast()
                    siftDown(from: 0)

                    // Runtime guard: verify heap root ordering against children; if violated, rebuild heap.
                    if elements.count > 1 {
                        let root = elements[0]
                        let l = 1
                        let r = 2
                        var violation = false
                        if l < elements.count && areSorted(elements[l], root) { violation = true }
                        if r < elements.count && areSorted(elements[r], root) { violation = true }
                        if violation {
                            // Rebuild heap to recover non-fatally.
                            var i = (elements.count / 2) - 1
                            while i >= 0 {
                                siftDown(from: i)
                                if i == 0 { break }
                                i -= 1
                            }
                        }
                    }

                    return root
                }

                var isEmpty: Bool {
                    elements.isEmpty
                }
            }

            // Comparator: older date first, if equal date then larger size first.
            var heap = Heap(elements: files) { a, b in
                if a.date == b.date { return a.size > b.size }
                return a.date < b.date
            }

            while total > stopThreshold && !heap.isEmpty {
                if Task.isCancelled { break }
                guard let entry = heap.pop() else { break }
                do {
                    let sidecarFailure = try delete(entry.url)
                    bytesFreed += entry.size
                    filesDeleted += 1
                    total -= entry.size
                    if let sf = sidecarFailure { failures.append(sf) }
                } catch {
                    let ns = error as NSError
                    failures.append(CacheTrimFailure(url: entry.url, domain: ns.domain, code: ns.code, message: ns.localizedDescription))
                }
                bytesSinceLastEmit += entry.size
                if filesDeleted % progressBatch == 0 {
                    emitProgress()
                }
                maybeFlushPending()
                if let byteThreshold = bytes, bytesSinceLastEmit >= byteThreshold {
                    emitProgress()
                }
                maybeFlushPending()
                if total <= stopThreshold {
                    break
                }
            }
            if filesDeleted > 0 {
                emitProgress(force: true)
            }
            return CacheTrimResult(
                bytesFreed: bytesFreed,
                filesDeleted: filesDeleted,
                failures: failures,
                lockAcquired: lockAcquired,
                recencyPolicy: policy,
                lockAttempts: lockAttempts,
                lockWaitNanos: lockWaitNanos
            )
        }

        // Full sort and bulk processing fallback.
        // Evict oldest first; for equal recency, prefer larger files to maximize bytes freed per delete.
        files.sort { lhs, rhs in
            if lhs.date == rhs.date { return lhs.size > rhs.size }
            return lhs.date < rhs.date
        }

        for entry in files {
            if Task.isCancelled { break }
            do {
                let sidecarFailure = try delete(entry.url)
                bytesFreed += entry.size
                filesDeleted += 1
                total -= entry.size
                if let sf = sidecarFailure { failures.append(sf) }
            } catch {
                let ns = error as NSError
                failures.append(CacheTrimFailure(url: entry.url, domain: ns.domain, code: ns.code, message: ns.localizedDescription))
            }
            bytesSinceLastEmit += entry.size
            if filesDeleted % progressBatch == 0 {
                emitProgress()
            }
            maybeFlushPending()
            if let byteThreshold = bytes, bytesSinceLastEmit >= byteThreshold {
                emitProgress()
            }
            maybeFlushPending()
            if let interval = timePacing, DispatchTime.now() >= lastEmitTime + .milliseconds(Int(interval * 1000)) {
                emitProgress()
            }
            maybeFlushPending()
            if total <= stopThreshold {
                break
            }
        }
        if filesDeleted > 0 {
            emitProgress(force: true)
        }

        return CacheTrimResult(
            bytesFreed: bytesFreed,
            filesDeleted: filesDeleted,
            failures: failures,
            lockAcquired: lockAcquired,
            recencyPolicy: policy,
            lockAttempts: lockAttempts,
            lockWaitNanos: lockWaitNanos
        )
    }

    private func acquireLockAsync(
        in cacheDir: URL,
        timeout: TimeInterval,
        retryInterval: TimeInterval,
        completion: @escaping (FileLock?, Int, UInt64) -> Void
    ) {
        let lock = FileLock(directory: cacheDir)
        let safeTimeout = max(0, min(timeout, 60))
        let start = DispatchTime.now()
        let deadline = start + .nanoseconds(Int(safeTimeout * 1_000_000_000))
        var attempts = 0

        func attempt() {
            if Task.isCancelled {
                lock.unlock()
                let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                completion(nil, attempts, elapsedNanos)
                return
            }
            do {
                let success = try lock.tryLockOnce()
                if success {
                    let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    completion(lock, attempts + 1, elapsedNanos)
                } else {
                    attempts += 1
                    let now = DispatchTime.now()
                    if now >= deadline {
                        lock.unlock()
                        let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                        completion(nil, attempts, elapsedNanos)
                    } else {
                        let safeRetry = min(max(0, retryInterval), 1.0)
                        ioQueue.asyncAfter(deadline: .now() + safeRetry) {
                            attempt()
                        }
                    }
                }
            } catch {
                lock.unlock()
                let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                completion(nil, attempts, elapsedNanos)
            }
        }

        ioQueue.async { attempt() }
    }

    /// Performs a single-pass enumeration to collect all eligible files with their sizes and recency date,
    /// while accumulating the total size. It samples early entries to decide whether accessDate is usable.
    private func collectFilesAndTotal(in dir: URL) -> (files: [(url: URL, size: Int64, date: Date)], total: Int64, policy: CacheRecencyPolicy) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .contentAccessDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], 0, .modificationDate) }

        var files: [(URL, Int64, Date)] = []
        var total: Int64 = 0

        // Sampling state to decide whether to rely on accessDate at all.
        let sampleLimit = self.accessSampleLimit
        let threshold = self.accessDateThreshold
        var sampled: [(url: URL, size: Int64, access: Date?, mod: Date?)] = []
        sampled.reserveCapacity(sampleLimit)
        var sampledEligible = 0
        var hasAccessCount = 0
        var decided = false
        var useAccessDate = false

        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            do {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .contentAccessDateKey, .fileSizeKey])
                if values.isDirectory == true { continue }
                if isMetadataSidecar(fileURL) { continue }
                let size = Int64(values.fileSize ?? 0)
                let access = values.contentAccessDate
                let mod = values.contentModificationDate
                total += size

                if !decided {
                    sampled.append((fileURL, size, access, mod))
                    sampledEligible += 1
                    if access != nil { hasAccessCount += 1 }
                    if sampledEligible >= sampleLimit {
                        useAccessDate = Double(hasAccessCount) / Double(sampledEligible) >= threshold
                        decided = true
                        // Flush sampled entries with the chosen date policy
                        for item in sampled {
                            let date = (useAccessDate ? item.access : nil) ?? item.mod ?? .distantPast
                            files.append((item.url, item.size, date))
                        }
                        sampled.removeAll(keepingCapacity: true)
                    }
                } else {
                    let date = (useAccessDate ? access : nil) ?? mod ?? .distantPast
                    files.append((fileURL, size, date))
                }
            } catch { continue }
        }

        // If we never reached the sample limit, decide based on what we saw and flush.
        if !decided {
            useAccessDate = sampledEligible > 0 && (Double(hasAccessCount) / Double(sampledEligible) >= threshold)
            for item in sampled {
                let date = (useAccessDate ? item.access : nil) ?? item.mod ?? .distantPast
                files.append((item.url, item.size, date))
            }
            sampled.removeAll()
        }

        let policy: CacheRecencyPolicy = useAccessDate ? .accessDate : .modificationDate
        return (files, total, policy)
    }

    /// Lightweight scanning helper to compute total size, count, and decide recency policy without holding full file list.
    private func scanTotalAndPolicy(in dir: URL) -> (total: Int64, policy: CacheRecencyPolicy, count: Int) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .contentAccessDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, .modificationDate, 0) }

        let sampleLimit = self.accessSampleLimit
        let threshold = self.accessDateThreshold
        var sampledEligible = 0
        var hasAccessCount = 0
        var decided = false
        var useAccessDate = false

        var total: Int64 = 0
        var count: Int = 0

        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }
            do {
                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .contentAccessDateKey, .fileSizeKey])
                if values.isDirectory == true { continue }
                if isMetadataSidecar(fileURL) { continue }
                total += Int64(values.fileSize ?? 0)
                count += 1
                if !decided {
                    sampledEligible += 1
                    if values.contentAccessDate != nil { hasAccessCount += 1 }
                    if sampledEligible >= sampleLimit {
                        useAccessDate = Double(hasAccessCount) / Double(sampledEligible) >= threshold
                        decided = true
                    }
                }
            } catch { continue }
        }

        if !decided {
            useAccessDate = sampledEligible > 0 && (Double(hasAccessCount) / Double(sampledEligible) >= threshold)
        }
        let policy: CacheRecencyPolicy = useAccessDate ? .accessDate : .modificationDate
        return (total, policy, count)
    }

    /// Returns true if the URL points to a metadata sidecar file using a double-extension pattern,
    /// e.g., `foo.data.<metadataExtension>`. Files whose only extension equals the metadata extension
    /// are not treated as sidecars and will not be skipped.
    private func isMetadataSidecar(_ url: URL) -> Bool {
        guard url.pathExtension == metadataExtension else { return false }
        // Check that removing the metadata extension still leaves another extension.
        let base = url.deletingPathExtension()
        return !base.pathExtension.isEmpty
    }

    /// Deletes the primary file and best-effort deletes its metadata sidecar.
    /// - Throws: An error if the primary file could not be removed.
    /// - Returns: An optional CacheTrimFailure if sidecar deletion failed (does not affect accounting).
    private func delete(_ fileURL: URL) throws -> CacheTrimFailure? {
        let fm = FileManager.default
        do {
            try fm.removeItem(at: fileURL)
        } catch {
            throw error
        }
        // Sidecar metadata deletion is best-effort and does not affect accounting.
        let metaURL = fileURL.appendingPathExtension(metadataExtension)
        do {
            try fm.removeItem(at: metaURL)
            return nil
        } catch {
            let ns = error as NSError
            let sev: CacheTrimFailureSeverity = {
                // Prefer Cocoa domain mapping when available; otherwise fall back to POSIX codes.
                if ns.domain == NSCocoaErrorDomain {
                    // Not found / no such file
                    let notFoundCodes: Set<Int> = [NSFileNoSuchFileError]
                    if notFoundCodes.contains(ns.code) {
                        return .notFound
                    }
                    // Permission-related errors
                    let permissionCodes: Set<Int> = [
                        NSFileWriteNoPermissionError,
                        NSFileWriteVolumeReadOnlyError,
                        NSFileReadNoPermissionError
                    ]
                    if permissionCodes.contains(ns.code) {
                        return .permissionDenied
                    }
                    // Some Cocoa errors wrap POSIX codes in userInfo
                    if let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code {
                        switch posix {
                        case Int(ENOENT): return .notFound
                        case Int(EPERM), Int(EACCES): return .permissionDenied
                        default: break
                        }
                    }
                    return .other
                } else {
                    // POSIX domain or others
                    switch ns.code {
                    case Int(ENOENT):
                        return .notFound
                    case Int(EPERM), Int(EACCES):
                        return .permissionDenied
                    default:
                        return .other
                    }
                }
            }()
            return CacheTrimFailure(url: metaURL, domain: ns.domain, code: ns.code, message: ns.localizedDescription, severity: sev)
        }
    }
}
