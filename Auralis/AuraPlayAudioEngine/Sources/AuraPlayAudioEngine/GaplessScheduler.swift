import AVFoundation
import Foundation

public final class GaplessScheduler: GaplessScheduling, @unchecked Sendable {
    private let cacheManager: any MediaCacheManaging
    private let engineController: AudioEngineController
    private let fallbackWaitNanoseconds: UInt64

    public init(
        cacheManager: any MediaCacheManaging,
        engineController: AudioEngineController,
        fallbackWaitNanoseconds: UInt64 = 500_000_000
    ) {
        self.cacheManager = cacheManager
        self.engineController = engineController
        self.fallbackWaitNanoseconds = fallbackWaitNanoseconds
    }

    public func scheduleCurrent(fileURL: URL, startingFrame: AVAudioFramePositionValue = 0) async throws {
        try await engineController.scheduleCurrent(fileURL: fileURL, startingFrame: startingFrame)
    }

    public func prepareNext<M: AuraPlayableMedia>(_ media: M) async throws -> TransitionQuality {
        if await cacheManager.isCached(media) {
            let localURL = try await cacheManager.localFile(for: media)
            try await engineController.scheduleNext(fileURL: localURL)
            await engineController.armPreparedNextForGaplessTransition()
            return .gapless
        }

        await cacheManager.prefetch(media)
        return .briefGap
    }

    public func playPreparedNext() async {
        await engineController.playPreparedNext()
    }

    public func startAfterBriefGap<M: AuraPlayableMedia>(_ media: M) async throws {
        let localURL = try await waitForCachedFileOrPlayableFile(media)
        try await engineController.scheduleNext(fileURL: localURL)
        await engineController.playPreparedNext()
    }

    public func prepareNextAtBoundary(fileURL: URL) async throws -> AVAudioFramePositionValue {
        try await engineController.scheduleNextAtHostBoundary(fileURL: fileURL)
    }

    private func waitForCachedFileOrPlayableFile<M: AuraPlayableMedia>(_ media: M) async throws -> URL {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int(fallbackWaitNanoseconds)))
        while ContinuousClock.now < deadline {
            if await cacheManager.isCached(media) {
                return try await cacheManager.localFile(for: media)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        return try await cacheManager.localFileWhenPlayable(for: media, minimumPlayableBytes: 512_000)
    }
}

public struct EqualPowerCrossfadeCurve: Sendable {
    public init() {}

    public func volumes(progress: Double) -> (outgoing: Float, incoming: Float) {
        let t = min(max(progress, 0), 1)
        let outgoing = cos(t * .pi / 2)
        let incoming = sin(t * .pi / 2)
        return (Float(outgoing), Float(incoming))
    }
}

public struct CrossfadePlan: Equatable, Sendable {
    public let duration: TimeInterval
    public let startsAtFrameBeforeEnd: AVAudioFramePositionValue

    public init(duration: TimeInterval, sampleRate: Double) {
        let clampedDuration = min(max(duration, 0), 8)
        self.duration = clampedDuration
        self.startsAtFrameBeforeEnd = AVAudioFramePositionValue(clampedDuration * sampleRate)
    }
}

public final class AutoMixController: @unchecked Sendable {
    private let scheduler: GaplessScheduler
    private let engineController: AudioEngineController
    private let curve: EqualPowerCrossfadeCurve
    private let stateQueue = DispatchQueue(label: "com.auraplay.automix.state")
    private var rampTask: Task<Void, Never>?
    private var activeRampDuration: TimeInterval?
    private var rampGeneration = 0

    public init(
        scheduler: GaplessScheduler,
        engineController: AudioEngineController,
        curve: EqualPowerCrossfadeCurve = EqualPowerCrossfadeCurve()
    ) {
        self.scheduler = scheduler
        self.engineController = engineController
        self.curve = curve
    }

    deinit {
        stateQueue.sync {
            rampTask?.cancel()
        }
    }

    public func prepareNext<M: AuraPlayableMedia>(_ media: M, crossfadeDuration: TimeInterval) async throws -> TransitionQuality {
        let quality = try await scheduler.prepareNext(media)
        guard crossfadeDuration > 0, quality == .gapless else {
            return quality
        }
        await engineController.setInactiveVolume(0)
        return .gapless
    }

    public func crossfadePlan(duration: TimeInterval, sampleRate: Double = 48_000) -> CrossfadePlan {
        CrossfadePlan(duration: duration, sampleRate: sampleRate)
    }

    public func scheduleCrossfadeBeforeTrackEnd(
        duration: TimeInterval,
        remainingFrames: AVAudioFramePositionValue,
        sampleRate: Double? = nil,
        stepsPerSecond: Double = 60
    ) {
        let plan = crossfadePlan(duration: duration, sampleRate: sampleRate ?? engineController.renderSampleRate)
        let pollIntervalNanoseconds = Self.pollIntervalNanoseconds(stepsPerSecond: stepsPerSecond)
        let generation = prepareNextRampGeneration(activeDuration: plan.duration)
        let engineController = engineController
        let scheduler = scheduler
        let curve = curve
        let task = Task { [weak self, engineController, scheduler, curve] in
            let currentFrame = await engineController.currentRenderFrame()
            let framesBeforeRamp = max(0, remainingFrames - plan.startsAtFrameBeforeEnd)
            let startFrame = currentFrame + framesBeforeRamp
            let endFrame = startFrame + plan.startsAtFrameBeforeEnd
            await Self.runRenderTimedCrossfade(
                engineController: engineController,
                scheduler: scheduler,
                curve: curve,
                duration: plan.duration,
                startFrame: startFrame,
                endFrame: endFrame,
                pollIntervalNanoseconds: pollIntervalNanoseconds
            )
            self?.clearRampTask(generation: generation)
        }

        storeRampTask(task, generation: generation)
    }

    public func startCrossfade(duration: TimeInterval, stepsPerSecond: Double = 60) {
        guard duration > 0 else {
            return
        }

        let clampedDuration = min(max(duration, 0), 8)
        guard let generation = prepareIdleRampGeneration(activeDuration: clampedDuration) else {
            return
        }

        let pollIntervalNanoseconds = Self.pollIntervalNanoseconds(stepsPerSecond: stepsPerSecond)
        let engineController = engineController
        let scheduler = scheduler
        let curve = curve
        let task = Task { [weak self, engineController, scheduler, curve] in
            let startFrame = await engineController.currentRenderFrame()
            let endFrame = startFrame + AVAudioFramePositionValue(clampedDuration * engineController.renderSampleRate)
            await Self.runRenderTimedCrossfade(
                engineController: engineController,
                scheduler: scheduler,
                curve: curve,
                duration: clampedDuration,
                startFrame: startFrame,
                endFrame: endFrame,
                pollIntervalNanoseconds: pollIntervalNanoseconds
            )
            self?.clearRampTask(generation: generation)
        }

        storeRampTask(task, generation: generation)
    }

    public func updateNextTransitionDuration(_ duration: TimeInterval) {
        stateQueue.sync {
            guard rampTask == nil else {
                return
            }
            activeRampDuration = min(max(duration, 0), 8)
        }
    }

    public func applyCrossfadeProgress(_ progress: Double) async {
        await Self.applyCrossfadeProgress(
            progress,
            engineController: engineController,
            scheduler: scheduler,
            curve: curve
        )
    }

    private func prepareNextRampGeneration(activeDuration: TimeInterval) -> Int {
        stateQueue.sync {
            rampTask?.cancel()
            rampGeneration += 1
            activeRampDuration = activeDuration
            return rampGeneration
        }
    }

    private func prepareIdleRampGeneration(activeDuration: TimeInterval) -> Int? {
        stateQueue.sync {
            guard rampTask == nil || rampTask?.isCancelled == true else {
                return nil
            }
            rampGeneration += 1
            activeRampDuration = activeDuration
            return rampGeneration
        }
    }

    private func storeRampTask(_ task: Task<Void, Never>, generation: Int) {
        stateQueue.sync {
            guard rampGeneration == generation else {
                task.cancel()
                return
            }
            rampTask = task
        }
    }

    private func clearRampTask(generation: Int) {
        stateQueue.sync {
            guard rampGeneration == generation else {
                return
            }
            rampTask = nil
            activeRampDuration = nil
        }
    }

    private static func runRenderTimedCrossfade(
        engineController: AudioEngineController,
        scheduler: GaplessScheduler,
        curve: EqualPowerCrossfadeCurve,
        duration: TimeInterval,
        startFrame: AVAudioFramePositionValue,
        endFrame: AVAudioFramePositionValue,
        pollIntervalNanoseconds: UInt64
    ) async {
        let clampedDuration = min(max(duration, 0), 8)
        guard clampedDuration > 0, endFrame > startFrame else {
            return
        }

        while !Task.isCancelled, await engineController.currentRenderFrame() < startFrame {
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        guard !Task.isCancelled else {
            return
        }

        await engineController.startInactivePlaybackForOverlap()
        let rampFrameCount = max(1, endFrame - startFrame)
        while !Task.isCancelled {
            let currentFrame = await engineController.currentRenderFrame()
            let progress = Double(currentFrame - startFrame) / Double(rampFrameCount)
            await applyCrossfadeProgress(
                progress,
                engineController: engineController,
                scheduler: scheduler,
                curve: curve
            )
            if progress >= 1 {
                break
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
    }

    private static func applyCrossfadeProgress(
        _ progress: Double,
        engineController: AudioEngineController,
        scheduler: GaplessScheduler,
        curve: EqualPowerCrossfadeCurve
    ) async {
        let volumes = curve.volumes(progress: progress)
        await engineController.setActiveVolume(volumes.outgoing)
        await engineController.setInactiveVolume(volumes.incoming)

        if progress >= 1 {
            await scheduler.playPreparedNext()
            await engineController.setActiveVolume(1)
            await engineController.stopInactiveWhenSilent()
        }
    }

    private static func pollIntervalNanoseconds(stepsPerSecond: Double) -> UInt64 {
        UInt64((1 / max(stepsPerSecond, 1)) * 1_000_000_000)
    }
}
