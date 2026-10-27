import AVFoundation
import Foundation

public final class EngineRecoveryCoordinator: @unchecked Sendable {
    public var events: AsyncStream<EngineRecoveryEvent> {
        eventsBroadcast.stream()
    }

    private let audioSessionManager: any AudioSessionManaging
    private let engineController: AudioEngineController
    private let notificationCenter: NotificationCenter
    private let eventsBroadcast = AsyncBroadcast<EngineRecoveryEvent>()
    private var eventTask: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?

    public init(
        audioSessionManager: any AudioSessionManaging,
        engineController: AudioEngineController,
        notificationCenter: NotificationCenter = .default
    ) {
        self.audioSessionManager = audioSessionManager
        self.engineController = engineController
        self.notificationCenter = notificationCenter
    }

    deinit {
        stop()
        eventsBroadcast.finish()
    }

    public func start() {
        guard eventTask == nil else {
            return
        }

        configurationObserver = notificationCenter.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.recoverFromConfigurationChange()
            }
        }

        // Subscribe before spawning the task so events yielded in the gap are buffered, not dropped.
        let events = audioSessionManager.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else {
                    return
                }
                await self.handle(event)
            }
        }
    }

    public func stop() {
        eventTask?.cancel()
        eventTask = nil

        if let configurationObserver {
            notificationCenter.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    public func recoverFromConfigurationChange() async {
        let frame = await engineController.currentFrame()
        do {
            try await engineController.restartPreservingGraph()
            try await engineController.rescheduleCurrentFromLastFile(startingFrame: frame)
            eventsBroadcast.yield(.configurationChanged(resumeFrame: frame))
        } catch {
            eventsBroadcast.yield(.failed(.engineStartFailed))
        }
    }

    public func publishBuffering(mediaID: String, frame: AVAudioFramePositionValue) {
        eventsBroadcast.yield(.buffering(mediaID: mediaID, frame: frame))
    }

    public func publishRecovered(mediaID: String, frame: AVAudioFramePositionValue) {
        eventsBroadcast.yield(.recovered(mediaID: mediaID, frame: frame))
    }

    public func recoverFromProgressiveUnderrun(
        mediaID: String,
        frame: AVAudioFramePositionValue,
        currentBytesAvailable: Int64,
        progress: AsyncStream<CacheProgress>
    ) async {
        await recoverFromProgressiveUnderrun(
            mediaID: mediaID,
            frame: frame,
            currentBytesAvailable: currentBytesAvailable,
            progress: progress,
            reschedule: nil
        )
    }

    public func recoverFromProgressiveUnderrun(
        mediaID: String,
        frame: AVAudioFramePositionValue,
        currentBytesAvailable: Int64,
        progress: AsyncStream<CacheProgress>,
        reschedule: (@Sendable (AVAudioFramePositionValue) async throws -> Void)?
    ) async {
        await engineController.pause()
        eventsBroadcast.yield(.buffering(mediaID: mediaID, frame: frame))
        for await update in progress where update.mediaID == mediaID {
            if update.state == .cached || update.bytesWritten > currentBytesAvailable {
                do {
                    if let reschedule {
                        try await reschedule(frame)
                    } else {
                        try await engineController.rescheduleCurrentFromLastFile(startingFrame: frame)
                    }
                    eventsBroadcast.yield(.recovered(mediaID: mediaID, frame: frame))
                } catch {
                    eventsBroadcast.yield(.failed(.engineStartFailed))
                }
                return
            }
        }
    }

    public func watchdogStart(retryDelayNanoseconds: UInt64 = 250_000_000) async throws {
        do {
            try await engineController.start()
        } catch {
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            do {
                try await engineController.start()
            } catch {
                eventsBroadcast.yield(.failed(.engineStartFailed))
                throw AuraPlayError.engineStartFailed
            }
        }
    }

    private func handle(_ event: AudioSessionEvent) async {
        switch event {
        case .shouldPause, .interruptionBegan:
            await engineController.pause()
            eventsBroadcast.yield(
                .paused(reason: event == .shouldPause ? .routeUnavailable : .interruptionBegan)
            )
        case .routeAvailable, .spatialAudioEnabledChanged:
            break
        case .interruptionEnded(let shouldResume):
            let frame = await engineController.currentFrame()
            do {
                try await engineController.restartPreservingGraph()
                try await engineController.rescheduleCurrentFromLastFile(startingFrame: frame)
                if shouldResume {
                    try await engineController.resume()
                }
                eventsBroadcast.yield(.interruptionRestored(shouldResume: shouldResume, resumeFrame: frame))
            } catch {
                eventsBroadcast.yield(.failed(.engineStartFailed))
            }
        }
    }
}
