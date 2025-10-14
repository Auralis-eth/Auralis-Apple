import Foundation
import AVFoundation
import Combine
import MediaPlayer

@MainActor
public final class PlaybackController: ObservableObject {
    // Dependencies
    let graph: AudioGraph
    let session: AudioSessionManager
    let preloader: Preloader
    var queue: QueueManager
    let crossfade: CrossfadeCoordinator
    let nowPlaying: NowPlayingService

    // Config
    let crossfadeSeconds: TimeInterval
    let skipInterval: TimeInterval

    // State
    @Published var snapshot: PlaybackSnapshot
    @Published public var lastError: PlaybackError? = nil
    var currentFile: AVAudioFile?
    var seekPosition: TimeInterval = 0

    // Transition / advance control
    var nextPending: (nft: NFT, file: AVAudioFile)?
    var isAdvancing: Bool = false
    var advanceSequence: Int = 0
    var crossfadeSwapWorkItem: DispatchWorkItem?
    var swapSequence: Int = 0

    // System integration state
    var wasPlayingBeforeInterruption: Bool = false
    var notificationObservers: [NSObjectProtocol] = []
    var preloadTasks: [Task<Void, Never>] = []

    // Remote command center state
    var remoteCommandTokens: [(command: MPRemoteCommand, token: Any)] = []
    var remoteCommandsRegistered: Bool = false

    internal init(graph: AudioGraph,
                session: AudioSessionManager,
                preloader: Preloader,
                queue: QueueManager,
                crossfade: CrossfadeCoordinator,
                nowPlaying: NowPlayingService,
                crossfadeSeconds: TimeInterval = 2.0,
                skipInterval: TimeInterval = 10.0) {
        self.graph = graph
        self.session = session
        self.preloader = preloader
        self.queue = queue
        self.crossfade = crossfade
        self.nowPlaying = nowPlaying
        self.crossfadeSeconds = crossfadeSeconds
        self.skipInterval = skipInterval
        self.snapshot = PlaybackSnapshot(state: .stopped, track: nil, elapsed: 0, duration: 0, canSkipNext: false, canSkipPrevious: false)
        setupNotifications()
        setupRemoteCommands()
        updateRemoteCommandStates()
    }

    deinit {
        for obs in notificationObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        notificationObservers.removeAll()
        for t in preloadTasks { t.cancel() }
        preloadTasks.removeAll()

        // Remove remote command targets to avoid duplicate handlers and leaks
        for (command, token) in remoteCommandTokens {
            command.removeTarget(token)
        }
        remoteCommandTokens.removeAll()
        remoteCommandsRegistered = false
    }

    func loadAndPlay(nft: NFT) async {
        await cancelCrossfade()
        do {
            try session.configureAndActivate()
        } catch {
            handleFatalError(.activationFailed)
            return
        }
        do {
            let file = try await openFile(for: nft)
            // Fresh load: no crossfade path. Apply immediately as current.
            nextPending = nil
            applyCurrent(nft: nft, file: file)
            try graph.ensureStarted()
            scheduleFromCurrentPosition()
            graph.playCurrent()
            if !commitState(.playing) { print("[PlaybackController] commitState(.playing) rejected in loadAndPlay") }
            pushNowPlaying()
            maybePreloadNext()
        } catch {
            let category = categorizePlaybackError(error)
            handleFatalError(category)
        }
    }
}

