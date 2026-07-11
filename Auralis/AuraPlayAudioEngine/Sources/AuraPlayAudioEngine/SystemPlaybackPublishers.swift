import Foundation

#if canImport(MediaPlayer)
import MediaPlayer
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

public final class NowPlayingPublisher: NowPlayingPublishing, @unchecked Sendable {
    public var lastSnapshot: NowPlayingInfoSnapshot? {
        stateQueue.sync { storedLastSnapshot }
    }

    private let elapsedTickInterval: TimeInterval
    private let publishesToSystem: Bool
    private let stateQueue = DispatchQueue(label: "com.auraplay.now-playing-publisher.state")
    private var storedLastSnapshot: NowPlayingInfoSnapshot?
    private var elapsedTask: Task<Void, Never>?

    public init(elapsedTickInterval: TimeInterval = 0.5, publishesToSystem: Bool = true) {
        self.elapsedTickInterval = elapsedTickInterval
        self.publishesToSystem = publishesToSystem
    }

    deinit {
        stateQueue.sync {
            elapsedTask?.cancel()
        }
    }

    public func update(_ state: NowPlayingState) async {
        setLastSnapshot(snapshot(from: state))

        #if canImport(MediaPlayer)
        guard publishesToSystem else {
            return
        }

        await MainActor.run {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: state.title,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: state.elapsedTime,
                MPNowPlayingInfoPropertyPlaybackRate: state.playbackRate,
                MPNowPlayingInfoPropertyMediaType: state.mediaType == .video
                    ? MPNowPlayingInfoMediaType.video.rawValue
                    : MPNowPlayingInfoMediaType.audio.rawValue,
            ]

            if let artist = state.artist {
                info[MPMediaItemPropertyArtist] = artist
            }
            if let duration = state.duration {
                info[MPMediaItemPropertyPlaybackDuration] = duration
            }
            if let artwork = Self.makeArtwork(from: state.artworkData) {
                info[MPMediaItemPropertyArtwork] = artwork
            }

            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
        #endif
    }

    public func startElapsedTimeUpdates(from state: NowPlayingState) {
        let task: Task<Void, Never>?
        let snapshot = snapshot(from: state)
        if state.playbackRate == 0 {
            task = nil
        } else {
            let startedAt = Date()
            let tickNanoseconds = UInt64(elapsedTickInterval * 1_000_000_000)
            task = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: tickNanoseconds)
                    guard !Task.isCancelled, let self else {
                        return
                    }
                    await self.publishElapsedTick(from: state, startedAt: startedAt)
                }
            }
        }

        stateQueue.sync {
            elapsedTask?.cancel()
            storedLastSnapshot = snapshot
            elapsedTask = task
        }
    }

    public func stopElapsedTimeUpdates() {
        stateQueue.sync {
            elapsedTask?.cancel()
            elapsedTask = nil
        }
    }

    public func publishElapsedTick(from state: NowPlayingState, startedAt: Date, now: Date = Date()) async {
        let elapsed = state.elapsedTime + now.timeIntervalSince(startedAt) * state.playbackRate
        await update(NowPlayingState(
            title: state.title,
            artist: state.artist,
            artworkData: state.artworkData,
            duration: state.duration,
            elapsedTime: elapsed,
            playbackRate: state.playbackRate,
            mediaType: state.mediaType
        ))
    }

    public func clear() async {
        stopElapsedTimeUpdates()
        setLastSnapshot(nil)
        #if canImport(MediaPlayer)
        guard publishesToSystem else {
            return
        }

        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        #endif
    }

    private func setLastSnapshot(_ snapshot: NowPlayingInfoSnapshot?) {
        stateQueue.sync {
            storedLastSnapshot = snapshot
        }
    }

    private func snapshot(from state: NowPlayingState) -> NowPlayingInfoSnapshot {
        NowPlayingInfoSnapshot(
            title: state.title,
            artist: state.artist,
            hasArtwork: state.artworkData != nil,
            duration: state.duration,
            elapsedTime: state.elapsedTime,
            playbackRate: state.playbackRate,
            mediaType: state.mediaType
        )
    }

    #if canImport(MediaPlayer)
    private static func makeArtwork(from data: Data?) -> MPMediaItemArtwork? {
        guard let data else {
            return nil
        }

        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            return nil
        }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            return nil
        }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        #else
        return nil
        #endif
    }
    #endif
}

public final class RemoteCommandPublisher: RemoteCommandPublishing, @unchecked Sendable {
    public var events: AsyncStream<RemoteCommandEvent> {
        eventsBroadcast.stream()
    }

    private let eventsBroadcast = AsyncBroadcast<RemoteCommandEvent>()
    #if canImport(MediaPlayer)
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    #endif

    public init(registerSystemCommands: Bool = true) {
        if registerSystemCommands {
            registerCommands()
        }
    }

    deinit {
        unregisterCommands()
        eventsBroadcast.finish()
    }

    public func simulate(_ event: RemoteCommandEvent) {
        eventsBroadcast.yield(event)
    }

    private func registerCommands() {
        #if canImport(MediaPlayer)
        let commandCenter = MPRemoteCommandCenter.shared()
        storeTarget(for: commandCenter.playCommand) { [weak self] _ in
            self?.eventsBroadcast.yield(.play)
            return .success
        }
        storeTarget(for: commandCenter.pauseCommand) { [weak self] _ in
            self?.eventsBroadcast.yield(.pause)
            return .success
        }
        storeTarget(for: commandCenter.togglePlayPauseCommand) { [weak self] _ in
            self?.eventsBroadcast.yield(.togglePlayPause)
            return .success
        }
        storeTarget(for: commandCenter.nextTrackCommand) { [weak self] _ in
            self?.eventsBroadcast.yield(.next)
            return .success
        }
        storeTarget(for: commandCenter.previousTrackCommand) { [weak self] _ in
            self?.eventsBroadcast.yield(.previous)
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        storeTarget(for: commandCenter.skipForwardCommand) { [weak self] _ in
            self?.eventsBroadcast.yield(.skipForward(15))
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        storeTarget(for: commandCenter.skipBackwardCommand) { [weak self] _ in
            self?.eventsBroadcast.yield(.skipBackward(15))
            return .success
        }
        storeTarget(for: commandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.eventsBroadcast.yield(.changePlaybackPosition(positionEvent.positionTime))
            return .success
        }
        #endif
    }

    private func unregisterCommands() {
        #if canImport(MediaPlayer)
        commandTargets.forEach { command, target in
            command.removeTarget(target)
        }
        commandTargets.removeAll()
        #endif
    }

    #if canImport(MediaPlayer)
    private func storeTarget(for command: MPRemoteCommand, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }
    #endif
}
