import Foundation
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif

/// Coordinates crossfade scheduling and transitions between audio files.
@MainActor
public final class CrossfadeCoordinator {
    private let graph: AudioGraph
    private var startTimer: DispatchSourceTimer?
    private var flipTimer: DispatchSourceTimer?
    private var primeTimer: DispatchSourceTimer?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var scheduleSequence: UInt = 0

    // MARK: - Thresholds & Tunables (centralized)
    private static let flipImmediateThresholdSeconds: TimeInterval = 0.005   // <= 5 ms: flip now
    private static let startGuardThresholdSeconds: TimeInterval = 0.005      // <= 5 ms: treat start as immediate
    private static let minDispatchDeltaSeconds: TimeInterval = 0.001         // <= 1 ms: consider timer as due

    private static let safetyFadeBaseSeconds: TimeInterval = 0.03            // 30 ms safety fade
    private static let safetyMinFloorSeconds: TimeInterval = 0.005           // 5 ms minimum safety floor
    private static let safetyMaxFloorSeconds: TimeInterval = 0.01            // 10 ms maximum safety floor
    private static let endGuardSeconds: TimeInterval = 0.05                  // 50 ms guard near end-of-file
    private static let safeMaximumOverlapSeconds: TimeInterval = 10.0        // cap crossfade overlap at 10s
    private static let microFadeDefaultSeconds: TimeInterval = 0.015         // 15 ms micro-fade for immediate flips
    private static let minCrossfadeRampSeconds: TimeInterval = 0.02          // minimum ramp time when ramping

    private static let adaptiveLeewayMinMs: Int = 5
    private static let adaptiveLeewayMaxMs: Int = 50

    private static let basePrimeLeadMin: TimeInterval = 0.02
    private static let basePrimeLeadMax: TimeInterval = 0.10
    private static let preStartLeadMin: TimeInterval = 0.02
    private static let preStartLeadMax: TimeInterval = 0.18
    private static let ioLeadMultiplier: Double = 2.0

    // MARK: - Reschedule bounds
    private static let maxRescheduleAttempts: Int = 2

    // Linear headroom (0.0 – 1.0). For example, 0.1 yields a max gain of 0.9
    public var outputHeadroom: Float = 0.0

    // Minimum non-zero crossfade floor in seconds. Default 50 ms to avoid abrupt transitions.
    public var minimumOverlapFloor: TimeInterval = 0.05

    // Optional provider for current playback position (in seconds) of the current path
    public var currentPositionProvider: (() -> TimeInterval)?

    // Optional callback invoked when an audio session interruption ends.
    // The boolean parameter indicates whether the system suggests resuming playback.
    public var onInterruptionEnded: ((Bool) -> Void)?

    // Optional callback to signal the app should present a manual resume hint/toast when the system doesn't auto-resume.
    public var onManualResumeSuggested: (() -> Void)?

    // Default attenuation floor for the next path during route-change fades (0.0 – 1.0).
    // Using a floor avoids fully silencing intros if the next path is active.
    public var routeChangeNextAttenuationFloor: Float = 0.5

    // Error callback for scheduling / playback failures
    public var onSchedulingError: ((Error) -> Void)?
    // Callback when rescheduling exceeds bounded attempts
    public var onExcessiveReschedules: ((Int) -> Void)?

    // Errors surfaced by the coordinator
    public enum CrossfadeError: Error {
        case engineNotRunning
        case invalidFile
        case schedulingFailed(reason: String)
        case playbackStartFailed(reason: String)
        case excessiveReschedules(attempts: Int)
    }

    public init(graph: AudioGraph) {
        self.graph = graph
        // Observe audio session interruptions and route changes to keep scheduling safe
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        }
        routeChangeObserver = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleRouteChange(note)
        }
    }

    @MainActor deinit {
        // Remove observers
        if let token = interruptionObserver { NotificationCenter.default.removeObserver(token) }
        if let token = routeChangeObserver { NotificationCenter.default.removeObserver(token) }
        interruptionObserver = nil
        routeChangeObserver = nil
        // Ensure any scheduled timers are cancelled to avoid callbacks after teardown
        self.cancel()
    }

    @MainActor public func cancel() {
        // Invalidate any in-flight scheduled work
        self.scheduleSequence &+= 1
        // Capture current timers and clear references first to avoid reuse races
        let st = self.startTimer; self.startTimer = nil
        let ft = self.flipTimer; self.flipTimer = nil
        let pt = self.primeTimer; self.primeTimer = nil

        if let st {
            st.setEventHandler {}
            st.cancel()
        }
        if let ft {
            ft.setEventHandler {}
            ft.cancel()
        }
        if let pt {
            pt.setEventHandler {}
            pt.cancel()
        }
    }

    // Safely convert seconds to nanoseconds for DispatchTime, with sane upper bound to avoid overflow
    private func clampedNanoseconds(from seconds: TimeInterval, maxSeconds: TimeInterval = 60.0) -> Int {
        let s = max(0.0, min(seconds, maxSeconds))
        let nsDouble = s * 1_000_000_000.0
        if nsDouble >= Double(Int.max) { return Int.max }
        if nsDouble <= 0 { return 0 }
        return Int(nsDouble)
    }

    public func scheduleCrossfade(currentFile: AVAudioFile,
                                  nextFile: AVAudioFile,
                                  overlap: TimeInterval,
                                  startDelay: TimeInterval,
                                  peakGain: Float = 0.9) {
        self.cancel()
        let token = self.scheduleSequence

        // Preflight checks: ensure engine is running and file is valid
        if let eng = self.graph.currentMixer.engine, !eng.isRunning {
            self.onSchedulingError?(CrossfadeError.engineNotRunning)
            self.cancel()
            return
        }
        if nextFile.length == 0 || nextFile.processingFormat.sampleRate <= 0 {
            self.onSchedulingError?(CrossfadeError.invalidFile)
            self.cancel()
            return
        }

        // Validate inputs: clamp peak gain and cap overlap to remaining duration to avoid overruns
        let maxAllowedPeak = max(0.0, 1.0 - outputHeadroom)
        let clampedPeakGain = min(maxAllowedPeak, max(0.0, peakGain))
        let sampleRate = currentFile.processingFormat.sampleRate
        let fileDuration = sampleRate > 0 ? Double(currentFile.length) / sampleRate : 0
        let safeMaximumOverlap: TimeInterval = Self.safeMaximumOverlapSeconds // seconds; conservative cap to avoid excessively long fades
        let positionSeconds = currentPositionProvider?() ?? 0
        // Remaining time on current, accounting for current playback position
        let remainingOnCurrent = max(0.0, fileDuration - positionSeconds)
        // Small guard to ensure we don't run right up against the end of file
        let endGuard: TimeInterval = Self.endGuardSeconds
        // Desired overlap cannot exceed what remains after the planned start delay and guard
        let maxAllowedByRemaining = max(0.0, remainingOnCurrent - startDelay - endGuard)
        let desiredOverlap = max(0.0, min(overlap, safeMaximumOverlap))
        let clampedOverlap = min(desiredOverlap, maxAllowedByRemaining)

        // Enforce a minimum non-zero crossfade when overlap was requested but clamped to zero by bounds
        // Allow callers to tune the floor by content type using `minimumOverlapFloorProvider`
        let defaultFloor = max(0.0, min(0.25, minimumOverlapFloor)) // clamp to [0, 250ms]
        let minNonZeroOverlap: TimeInterval = defaultFloor

        let effectiveOverlap: TimeInterval = {
            if desiredOverlap > 0.0, maxAllowedByRemaining > 0.0 {
                return max(minNonZeroOverlap, min(desiredOverlap, maxAllowedByRemaining))
            } else {
                return clampedOverlap
            }
        }()

        let zeroOverlapEdge = (desiredOverlap > 0.0) && (effectiveOverlap == 0.0)
        let safetyFadeBase: TimeInterval = Self.safetyFadeBaseSeconds // 30ms safety fade
        // Clamp safety fade by remaining time after startDelay and guard; skip if no time remains
        let safetyFadeClamped: TimeInterval = max(0.0, min(safetyFadeBase, maxAllowedByRemaining))
        // Enforce a tiny non-zero ramp (5–10 ms) when audio is active to avoid clicks
        let minSafetyFloor: TimeInterval = Self.safetyMinFloorSeconds
        let maxSafetyFloor: TimeInterval = Self.safetyMaxFloorSeconds
        let currentIsAudible = (self.graph.currentMixer.outputVolume > 0.0)
        let enforcedSafety: TimeInterval = {
            if zeroOverlapEdge && safetyFadeClamped == 0.0 && currentIsAudible && maxAllowedByRemaining > 0.0 {
                // Constrain by remaining time and the 5–10 ms window
                return min(maxSafetyFloor, max(minSafetyFloor, maxAllowedByRemaining))
            } else {
                return safetyFadeClamped
            }
        }()
        let crossfadeDuration: TimeInterval = zeroOverlapEdge ? enforcedSafety : effectiveOverlap
        let noRamp: Bool = crossfadeDuration <= 0.0
        let microFadeDuration: TimeInterval = Self.microFadeDefaultSeconds // 15 ms micro safety fade to prevent pops on immediate flips

        // Compute host times aligned to the engine's render clock when available for sample-accurate sync
        let engine = self.graph.currentMixer.engine
        let baseHost: UInt64
        let usedMachFallback: Bool
        if let engine, engine.isRunning, let lastRenderTime = engine.outputNode.lastRenderTime {
            baseHost = lastRenderTime.hostTime
            usedMachFallback = false
        } else {
            baseHost = mach_absolute_time()
            usedMachFallback = true
        }

        let startHost = baseHost &+ AVAudioTime.hostTime(forSeconds: max(0, startDelay))
        let flipHost = noRamp ? (startHost &+ AVAudioTime.hostTime(forSeconds: microFadeDuration)) : (startHost &+ AVAudioTime.hostTime(forSeconds: max(Self.minCrossfadeRampSeconds, crossfadeDuration)))

        let nowHostSeconds = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let rawStartDelta = AVAudioTime.seconds(forHostTime: startHost) - nowHostSeconds
        let rawFlipDelta  = AVAudioTime.seconds(forHostTime: flipHost)  - nowHostSeconds

        // Bound the maximum deadline window by track context to avoid long pending timers near the end
        let contextUpperBound: TimeInterval = max(5.0, min(60.0, remainingOnCurrent + 0.5))
        let maxDeltaWindow: TimeInterval = contextUpperBound

        let normStartDelta = min(max(0, rawStartDelta), maxDeltaWindow)
        let normFlipDelta  = min(max(0, rawFlipDelta),  maxDeltaWindow)

        // Minimum time threshold to consider a deadline valid/future
        let minDelta: TimeInterval = Self.minDispatchDeltaSeconds

        let startDeadline = DispatchTime.now() + .nanoseconds(clampedNanoseconds(from: normStartDelta, maxSeconds: maxDeltaWindow))
        let flipDeadline  = DispatchTime.now() + .nanoseconds(clampedNanoseconds(from: normFlipDelta,  maxSeconds: maxDeltaWindow))

        var rescheduleCount = 0
        let maxRescheduleCount = Self.maxRescheduleAttempts

        // Adaptive leeway: ~1% of overlap duration (ms), clamped to [5, 50] to balance precision and energy
        let adaptiveLeewayMs = Int(max(Double(Self.adaptiveLeewayMinMs), min(Double(Self.adaptiveLeewayMaxMs), crossfadeDuration * 10.0)))

        // Compute prime lead based on IO buffer duration (x2), clamped to [20ms, 100ms]
        let ioLead = AVAudioSession.sharedInstance().ioBufferDuration
        let basePrimeLead = max(Self.basePrimeLeadMin, min(Self.basePrimeLeadMax, (ioLead > 0 ? ioLead * Self.ioLeadMultiplier : 0.05)))
        let preStartLeadSeconds: TimeInterval = max(Self.preStartLeadMin, min(Self.preStartLeadMax, basePrimeLead))

        // Pre-roll next
        let startTime = AVAudioTime(hostTime: startHost)
        self.graph.setNextPathVolume(0.0)
        self.graph.scheduleFileOnNext(nextFile, at: startTime)
        // Gate starting the next player to just before the scheduled start to avoid any pre-ramp audio
        let targetStartSeconds = AVAudioTime.seconds(forHostTime: startHost)
        let primeSeconds = max(0, targetStartSeconds - preStartLeadSeconds)
        let primeDeltaSeconds = max(0, primeSeconds - nowHostSeconds)

        let primeDeadline = DispatchTime.now() + .nanoseconds(clampedNanoseconds(from: primeDeltaSeconds, maxSeconds: maxDeltaWindow))
        let primeHandler: () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.scheduleSequence == token else { return }
                // Clear the reference after firing
                self.primeTimer = nil
                self.graph.playNext()

                // Simple timebase mismatch check with a single threshold (50 ms)
                let currentMismatch: Bool = {
                    guard let engine = self.graph.currentMixer.engine, engine.isRunning, let engineHostNow = engine.outputNode.lastRenderTime?.hostTime else { return usedMachFallback }
                    let engineNowSec = AVAudioTime.seconds(forHostTime: engineHostNow)
                    let machNowSec = AVAudioTime.seconds(forHostTime: mach_absolute_time())
                    guard engineNowSec.isFinite, machNowSec.isFinite else { return true }
                    let delta = abs(engineNowSec - machNowSec)
                    let threshold: Double = 0.05
                    return delta > threshold
                }()

                if (usedMachFallback || currentMismatch), let engine = self.graph.currentMixer.engine, engine.isRunning {
                    if let lrt = engine.outputNode.lastRenderTime {
                        if rescheduleCount >= maxRescheduleCount {
                            self.onExcessiveReschedules?(rescheduleCount)
                            self.onSchedulingError?(CrossfadeError.excessiveReschedules(attempts: rescheduleCount))
                            return
                        }
                        rescheduleCount &+= 1
                        // Recompute start/flip host times relative to the render clock
                        let newBaseHost = lrt.hostTime
                        let newStartHost = newBaseHost &+ AVAudioTime.hostTime(forSeconds: max(0, startDelay))
                        let newFlipHost  = noRamp ? newStartHost : (newStartHost &+ AVAudioTime.hostTime(forSeconds: max(Self.minCrossfadeRampSeconds, crossfadeDuration)))

                        self.rescheduleTimersFromNow(token: token,
                                                     startHost: newStartHost,
                                                     flipHost: newFlipHost,
                                                     noRamp: noRamp,
                                                     crossfadeDuration: crossfadeDuration,
                                                     clampedPeakGain: clampedPeakGain,
                                                     microFadeDuration: microFadeDuration,
                                                     maxDeltaWindow: maxDeltaWindow,
                                                     adaptiveLeewayMs: adaptiveLeewayMs,
                                                     nextFile: nextFile)
                    } else {
                        // Fallback: no render clock yet; realign using mach-relative deadlines or immediate ramp
                        if rescheduleCount >= maxRescheduleCount {
                            self.onExcessiveReschedules?(rescheduleCount)
                            self.onSchedulingError?(CrossfadeError.excessiveReschedules(attempts: rescheduleCount))
                            return
                        }
                        rescheduleCount &+= 1

                        self.rescheduleTimersFromNow(token: token,
                                                     startHost: startHost,
                                                     flipHost: flipHost,
                                                     noRamp: noRamp,
                                                     crossfadeDuration: crossfadeDuration,
                                                     clampedPeakGain: clampedPeakGain,
                                                     microFadeDuration: microFadeDuration,
                                                     maxDeltaWindow: maxDeltaWindow,
                                                     adaptiveLeewayMs: adaptiveLeewayMs,
                                                     nextFile: nextFile)
                    }
                }
            }
        }
        if primeDeltaSeconds < minDelta {
            // If the prime deadline is effectively now/past, execute immediately instead of scheduling
            primeHandler()
        } else {
            let pt = DispatchSource.makeTimerSource(queue: .main)
            pt.schedule(deadline: primeDeadline, leeway: .milliseconds(5))
            pt.setEventHandler(qos: .userInitiated, flags: [], handler: primeHandler)
            pt.resume()
            primeTimer = pt
        }

        if normStartDelta < minDelta {
            // Start deadline is effectively now: perform ramp immediately
            Task { @MainActor [weak self] in
                guard let self = self, self.scheduleSequence == token else { return }
                self.startTimer = nil
                if !noRamp {
                    self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: crossfadeDuration)
                    self.graph.ramp(mixer: self.graph.nextMixer, to: clampedPeakGain, duration: crossfadeDuration)
                } else {
                    // Apply a micro safety fade to avoid pops before flipping
                    self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: microFadeDuration)
                    self.graph.ramp(mixer: self.graph.nextMixer, to: clampedPeakGain, duration: microFadeDuration)
                }
            }
        } else {
            let st = DispatchSource.makeTimerSource(queue: .main)
            st.schedule(deadline: startDeadline, leeway: .milliseconds(adaptiveLeewayMs))
            st.setEventHandler(qos: .userInitiated, flags: [], handler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.scheduleSequence == token else { return }
                    self.startTimer = nil
                    if !noRamp {
                        self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: crossfadeDuration)
                        self.graph.ramp(mixer: self.graph.nextMixer, to: clampedPeakGain, duration: crossfadeDuration)
                    }
                }
            })
            st.resume()
            startTimer = st
        }

        if normFlipDelta < minDelta {
            // Flip deadline is effectively now: flip immediately
            Task { @MainActor [weak self] in
                guard let self = self, self.scheduleSequence == token else { return }
                self.flipTimer = nil
                self.graph.flipToNext(with: nextFile)
            }
        } else {
            let ft = DispatchSource.makeTimerSource(queue: .main)
            ft.schedule(deadline: flipDeadline, leeway: .milliseconds(adaptiveLeewayMs))
            ft.setEventHandler(qos: .userInitiated, flags: [], handler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, self.scheduleSequence == token else { return }
                    self.flipTimer = nil
                    self.graph.flipToNext(with: nextFile)
                }
            })
            ft.resume()
            flipTimer = ft
        }
    }

    // MARK: - Edge-case helpers
    // Returns true when the flip should occur immediately (deadline effectively due)
    private func shouldFlipImmediately(_ rawFlipDelta: TimeInterval) -> Bool {
        return rawFlipDelta <= Self.flipImmediateThresholdSeconds
    }

    // Returns true when the start is effectively immediate and we should not schedule a start timer
    private func isNearStart(_ rawStartDelta: TimeInterval) -> Bool {
        return rawStartDelta <= Self.startGuardThresholdSeconds
    }

    // Extracted from prime timer handler: reschedules start/flip timers relative to now using provided host times
    // Handles threshold guards, immediate flips, micro-fade behavior, and timer (re)creation.
    private func rescheduleTimersFromNow(token: UInt,
                                         startHost: UInt64,
                                         flipHost: UInt64,
                                         noRamp: Bool,
                                         crossfadeDuration: TimeInterval,
                                         clampedPeakGain: Float,
                                         microFadeDuration: TimeInterval,
                                         maxDeltaWindow: TimeInterval,
                                         adaptiveLeewayMs: Int,
                                         nextFile: AVAudioFile) {
        // Compute deltas relative to mach now
        let nowHostSeconds = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let rawStartDelta = AVAudioTime.seconds(forHostTime: startHost) - nowHostSeconds
        let rawFlipDelta  = AVAudioTime.seconds(forHostTime: flipHost)  - nowHostSeconds

        // Cancel any existing reschedule timers without invalidating the token
        let oldStart = self.startTimer; self.startTimer = nil
        let oldFlip  = self.flipTimer;  self.flipTimer  = nil
        if let oldStart {
            oldStart.setEventHandler {}
            oldStart.cancel()
        }
        if let oldFlip  {
            oldFlip.setEventHandler {}
            oldFlip.cancel()
        }

        guard self.scheduleSequence == token else { return }

        // Edge-case 1: flip is effectively due – flip immediately
        if shouldFlipImmediately(rawFlipDelta) {
            // Immediate flip: hard-ramp to targets and flip now
            self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: 0.0)
            self.graph.ramp(mixer: self.graph.nextMixer, to: clampedPeakGain, duration: 0.0)
            self.flipTimer = nil
            self.graph.flipToNext(with: nextFile)
            return
        }

        // Edge-case 2: start is effectively due – near-start handling
        if isNearStart(rawStartDelta) {
            if noRamp {
                // Apply a short micro-fade, then flip after the fade completes
                self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: microFadeDuration)
                self.graph.ramp(mixer: self.graph.nextMixer, to: clampedPeakGain, duration: microFadeDuration)
                let adjustedFlipDeadline = DispatchTime.now() + .nanoseconds(self.clampedNanoseconds(from: microFadeDuration, maxSeconds: 1.0))
                let adjFT = DispatchSource.makeTimerSource(queue: .main)
                adjFT.schedule(deadline: adjustedFlipDeadline, leeway: .milliseconds(2))
                adjFT.setEventHandler(qos: .userInitiated, flags: [], handler: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self, self.scheduleSequence == token else { return }
                        self.flipTimer = nil
                        self.graph.flipToNext(with: nextFile)
                    }
                })
                adjFT.resume()
                self.flipTimer = adjFT
                return
            } else {
                // Compute remaining ramp time and schedule flip after it
                let elapsed = max(0.0, -rawStartDelta)
                let remaining = max(0.01, max(0.0, crossfadeDuration - elapsed))
                self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: remaining)
                self.graph.ramp(mixer: self.graph.nextMixer, to: clampedPeakGain, duration: remaining)

                let adjustedFlipDeadline = DispatchTime.now() + .nanoseconds(self.clampedNanoseconds(from: remaining, maxSeconds: maxDeltaWindow))
                let adjFT = DispatchSource.makeTimerSource(queue: .main)
                adjFT.schedule(deadline: adjustedFlipDeadline, leeway: .milliseconds(adaptiveLeewayMs))
                adjFT.setEventHandler(qos: .userInitiated, flags: [], handler: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self, self.scheduleSequence == token else { return }
                        self.flipTimer = nil
                        self.graph.flipToNext(with: nextFile)
                    }
                })
                adjFT.resume()
                self.flipTimer = adjFT
                return
            }
        }

        // Standard path: schedule start and flip timers
        let newStartDeadline = DispatchTime.now() + .nanoseconds(self.clampedNanoseconds(from: rawStartDelta, maxSeconds: maxDeltaWindow))
        let newFlipDeadline  = DispatchTime.now() + .nanoseconds(self.clampedNanoseconds(from: max(0, rawFlipDelta), maxSeconds: maxDeltaWindow))

        let newST = DispatchSource.makeTimerSource(queue: .main)
        newST.schedule(deadline: newStartDeadline, leeway: .milliseconds(adaptiveLeewayMs))
        newST.setEventHandler(qos: .userInitiated, flags: [], handler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.scheduleSequence == token else { return }
                self.startTimer = nil
                if !noRamp {
                    self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: crossfadeDuration)
                    self.graph.ramp(mixer: self.graph.nextMixer, to: clampedPeakGain, duration: crossfadeDuration)
                }
            }
        })
        newST.resume()
        self.startTimer = newST

        let newFT = DispatchSource.makeTimerSource(queue: .main)
        newFT.schedule(deadline: newFlipDeadline, leeway: .milliseconds(adaptiveLeewayMs))
        newFT.setEventHandler(qos: .userInitiated, flags: [], handler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.scheduleSequence == token else { return }
                self.flipTimer = nil
                self.graph.flipToNext(with: nextFile)
            }
        })
        newFT.resume()
        self.flipTimer = newFT
    }

    // Approximate equal-power fade-out for route changes when no custom applier is provided.
    // We shape the current mixer with a cosine-based small fixed-step envelope and gently attenuate
    // the next mixer toward a configurable floor to avoid fully silencing active intros.
    private func applyDefaultEqualPowerRouteFade(duration: TimeInterval) {
        let token = self.scheduleSequence
        let d = max(0.0, duration)
        if d == 0 {
            Task { @MainActor in
                guard self.scheduleSequence == token else { return }
                self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: 0.0)
                self.graph.ramp(mixer: self.graph.nextMixer, to: 0.0, duration: 0.0)
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self, self.scheduleSequence == token else { return }
            // Single-envelope route fade to reduce scheduling/mixer thrash
            self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: d)
            // Gently attenuate next mixer toward a floor, but never raise it above its current level
            let currentNextLevel: Float = self.graph.nextMixer.outputVolume
            let clampedFloor = max(0.0, min(1.0, self.routeChangeNextAttenuationFloor))
            let targetNextLevel: Float = min(currentNextLevel, clampedFloor)
            self.graph.ramp(mixer: self.graph.nextMixer, to: targetNextLevel, duration: d)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            // Cancel any pending ramps/flip while interrupted
            self.cancel()
        case .ended:
            // Determine if the system indicates playback should resume
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            let shouldResume = options.contains(.shouldResume)
            // Notify host so it can reschedule or resume as appropriate
            self.onInterruptionEnded?(shouldResume)
            if !shouldResume {
                self.onManualResumeSuggested?()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Route change policy & helpers (decision table)
    private struct RouteFadePolicy {
        // Default durations when no explicit mapping exists
        static let defaultHeadphones: TimeInterval = 0.04
        static let defaultSpeakers: TimeInterval = 0.03

        // Per-reason durations for headphones
        static let headphones: [AVAudioSession.RouteChangeReason: TimeInterval] = [
            .newDeviceAvailable: 0.16,
            .routeConfigurationChange: 0.12,
            .categoryChange: 0.10,
            .override: 0.10,
            .oldDeviceUnavailable: 0.06,
            .noSuitableRouteForCategory: 0.03,
            .unknown: 0.04,
            .wakeFromSleep: 0.04,
        ]

        // Per-reason durations for speakers (or non-headphones)
        static let speakers: [AVAudioSession.RouteChangeReason: TimeInterval] = [
            .newDeviceAvailable: 0.12,
            .routeConfigurationChange: 0.10,
            .categoryChange: 0.08,
            .override: 0.08,
            .oldDeviceUnavailable: 0.05,
            .noSuitableRouteForCategory: 0.03,
            .unknown: 0.03,
            .wakeFromSleep: 0.03,
        ]
    }

    // Returns true if the current output route is headphone-like
    private func isHeadphonesOutput() -> Bool {
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        return currentRoute.outputs.contains { out in
            switch out.portType {
            case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                return true
            default:
                return false
            }
        }
    }

    // Returns the fade duration for a given route change reason using the decision table
    private func fadeDuration(for reason: AVAudioSession.RouteChangeReason, isHeadphones: Bool) -> TimeInterval {
        if isHeadphones {
            return RouteFadePolicy.headphones[reason] ?? RouteFadePolicy.defaultHeadphones
        } else {
            return RouteFadePolicy.speakers[reason] ?? RouteFadePolicy.defaultSpeakers
        }
    }

    // Applies the equal-power route fade and then cancels after the fade completes
    private func performRouteFadeThenCancel(duration: TimeInterval, token: UInt) {
        let d = max(0.0, duration)
        if d == 0 {
            Task { @MainActor in
                guard self.scheduleSequence == token else { return }
                self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: 0.0)
                self.graph.ramp(mixer: self.graph.nextMixer, to: 0.0, duration: 0.0)
            }
            return
        }
        self.applyDefaultEqualPowerRouteFade(duration: d)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((d * 1_000_000_000.0).rounded()))
            guard let self = self, self.scheduleSequence == token else { return }
            self.cancel()
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        let token = self.scheduleSequence

        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // Determine current output context once
        let headphones = isHeadphonesOutput()

        // Decide fade duration using the centralized policy
        let fadeOut: TimeInterval = fadeDuration(for: reason, isHeadphones: headphones)

        // Apply the common fade-then-cancel behavior
        performRouteFadeThenCancel(duration: fadeOut, token: token)
    }
}

