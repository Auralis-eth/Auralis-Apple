import Foundation
import AVFoundation

/// AudioGraph is confined to the main actor. Threading & audio thread behavior:
/// - All public APIs must be called from the main thread. The type is `@MainActor`,
///   and methods assert main-thread usage at runtime for additional safety.
/// - AVAudioEngine performs audio rendering on a real-time audio thread that is NOT the main thread.
///   Engine callbacks and internal processing may occur there; do not block that thread.
/// - Avoid cross-thread AVAudioNode property access. This class updates node graphs and most properties
///   on the main thread. The `ramp(…)` helper is a special case: it updates `AVAudioMixerNode.volume`
///   from a dedicated high-priority queue for tighter timing. Ensure this matches your app’s tolerance;
///   otherwise, prefer manual rendering or marshal updates to the main thread.
///
/// Safe usage patterns:
/// - Create and use `AudioGraph` only on the main thread.
/// - Call `start()`/`ensureStarted()` before scheduling/playing.
/// - Use `scheduleFile…` APIs on the main thread; they validate formats and prepare players.
/// - For smooth crossfades, call `ramp(mixer:to:duration:)` for both `currentMixer` and `nextMixer`.
/// - Use `resetGraph()` only when playback is stopped or when you’re prepared to rebuild the graph; it will stop the engine, rebuild, and then start it.
@MainActor
public final class AudioGraph {
    public enum GraphError: Error { case engineStartFailed(Error), fileLoadFailed(Error), incompatibleFormat(String) }

    private let engine = AVAudioEngine()
    private var playerA = AVAudioPlayerNode()
    private var playerB = AVAudioPlayerNode()
    private let mixerA = AVAudioMixerNode()
    private let mixerB = AVAudioMixerNode()
    private let engineLock = NSLock()

    /// Asserts the caller is on the main thread. All public APIs require main-thread access.
    @inline(__always) private func assertOnMainThread(file: StaticString = #fileID, line: UInt = #line) {
        precondition(Thread.isMainThread, "AudioGraph APIs must be called on the main thread.", file: file, line: line)
    }

    /// Acquire `engineLock` before calling. Ensures the AVAudioEngine is fully stopped.
    /// AVAudioEngine requires the engine to be stopped before any graph mutations
    /// (disconnect, detach, attach, reset). This method synchronously pauses and
    /// stops the engine and waits briefly for `isRunning` to reflect the stopped state.
    private func stopEngineLocked() {
        if engine.isRunning {
            engine.pause()
            engine.stop()
            // Wait briefly for the engine to fully transition to stopped
            var attempts = 0
            while engine.isRunning && attempts < 5 {
                Thread.sleep(forTimeInterval: 0.005)
                attempts += 1
            }
        }
    }

    /// Must be called while holding `engineLock`.
    /// Asserts the engine is stopped before performing graph mutations.
    private func assertEngineStoppedLocked(file: StaticString = #fileID, line: UInt = #line) {
        precondition(!engine.isRunning, "AVAudioEngine must be stopped before modifying the graph.", file: file, line: line)
    }

    /// Validates that the given AVAudioFile's processing format is compatible with this graph.
    /// Requirements:
    /// - PCM format (Float32 or Int16). Most decoded files will be Float32.
    /// - Sample rate must be positive; resampling is handled by the engine mixers.
    /// - Channel count must be 1 or 2 (mono or stereo). More channels are not supported here.
    ///
    /// Throws `GraphError.incompatibleFormat` with a descriptive message if invalid.
    private func validateFileFormat(_ file: AVAudioFile) throws {
        let fmt = file.processingFormat
        let channels = Int(fmt.channelCount)
        let sr = fmt.sampleRate
        let isPCM: Bool = {
            switch fmt.commonFormat {
            case .pcmFormatFloat32, .pcmFormatInt16: return true
            default: return false
            }
        }()
        guard isPCM else {
            throw GraphError.incompatibleFormat("Unsupported audio format. Expected PCM (Float32/Int16). Got: \(fmt)")
        }
        guard sr > 0 else {
            throw GraphError.incompatibleFormat("Invalid sample rate: \(sr)")
        }
        guard (1...2).contains(channels) else {
            throw GraphError.incompatibleFormat("Unsupported channel count: \(channels). Only mono/stereo supported.")
        }
    }

    /// Indicates which path is current (A when true, B when false). Read-only to callers.
    public private(set) var currentIsA = true

    /// Warning: Do not mutate returned nodes from outside this type. Use the provided APIs (`playCurrent`, `playNext`, `setCurrentPathVolume`, `setNextPathVolume`, `ramp`) to avoid corrupting the graph.
    /// Exposed as internal to discourage external interference from other modules.
    internal var currentPlayer: AVAudioPlayerNode { currentIsA ? playerA : playerB }
    internal var nextPlayer: AVAudioPlayerNode { currentIsA ? playerB : playerA }
    internal var currentMixer: AVAudioMixerNode { currentIsA ? mixerA : mixerB }
    internal var nextMixer: AVAudioMixerNode { currentIsA ? mixerB : mixerA }

    // Ramp infra: All access to rampTimers must occur on rampQueue. These are marked nonisolated(unsafe)
    // so we can mutate from rampQueue even though the class is @MainActor. Do NOT touch rampTimers
    // outside of rampQueue.{sync,async} blocks.
    nonisolated(unsafe) private let rampQueue = DispatchQueue(label: "audio.graph.ramp", qos: .userInteractive)
    nonisolated(unsafe) private var rampTimers: [ObjectIdentifier: DispatchSourceTimer] = [:]

    @MainActor deinit {
        // Thorough teardown to prevent timers firing post-deallocation and to release audio resources
        engineLock.lock()
        defer { engineLock.unlock() }

        // Cancel any active ramp timers first
        cancelAllRamps()

        // Stop players and engine
        playerA.stop()
        playerB.stop()
        mixerA.volume = 0
        mixerB.volume = 0
        stopEngineLocked()

        // Reset and dismantle the graph
        engine.reset()
        engine.disconnectNodeOutput(playerA)
        engine.disconnectNodeOutput(playerB)
        engine.disconnectNodeOutput(mixerA)
        engine.disconnectNodeOutput(mixerB)
        engine.detach(playerA)
        engine.detach(playerB)
        engine.detach(mixerA)
        engine.detach(mixerB)
    }

    private func cancelAllRamps() {
        // Cancel and clear any active ramp timers on the rampQueue to serialize access
        rampQueue.sync {
            for (_, timer) in rampTimers {
                timer.setEventHandler(handler: {})
                timer.cancel()
            }
            rampTimers.removeAll()
        }
    }

    /// Connections are created with format: nil to allow AVAudioEngine to negotiate formats and perform necessary sample-rate/channel conversions.
    public init() {
        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(mixerA)
        engine.attach(mixerB)

        engine.connect(playerA, to: mixerA, format: nil)
        engine.connect(mixerA, to: engine.mainMixerNode, format: nil)
        engine.connect(playerB, to: mixerB, format: nil)
        engine.connect(mixerB, to: engine.mainMixerNode, format: nil)
        mixerA.volume = 0
        mixerB.volume = 0
        engine.prepare()
    }

    /// Starts the engine if not already running. Serialized with engineLock; safe to call repeatedly.
    public func start() throws {
        assertOnMainThread()
        engineLock.lock()
        defer { engineLock.unlock() }
        if engine.isRunning { return }
        do {
            try engine.start()
        } catch {
            // If another thread started the engine between the check and this call,
            // treat it as a no-op to avoid surfacing spurious errors.
            if engine.isRunning { return }
            throw GraphError.engineStartFailed(error)
        }
    }

    /// Prepares and starts the engine if needed. Serialized with engineLock; safe to call repeatedly.
    public func ensureStarted() throws {
        assertOnMainThread()
        engineLock.lock()
        defer { engineLock.unlock() }
        if engine.isRunning { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            if engine.isRunning { return }
            throw GraphError.engineStartFailed(error)
        }
    }

    /// Safely stops playback and the engine. Cancels ramps, stops players, then synchronously stops the engine before clearing volumes.
    public func stop() {
        assertOnMainThread()
        // Stop playback and engine safely. Safe to call multiple times.
        // Ordering:
        // 1) Lock to serialize with other engine operations
        // 2) Cancel any volume ramps to avoid concurrent volume changes
        // 3) Stop players (safe while engine is running)
        // 4) Stop the engine synchronously
        // 5) Clear volumes
        engineLock.lock()
        defer { engineLock.unlock() }

        // Cancel ramps first to prevent concurrent UI/volume updates during teardown
        cancelAllRamps()

        // Stop player nodes if they were playing
        playerA.stop()
        playerB.stop()

        // Ensure the engine is fully stopped before leaving
        stopEngineLocked()

        // Clear path volumes after engine is stopped
        mixerA.volume = 0
        mixerB.volume = 0
    }

    /// Resets and rebuilds the audio graph. Requires main actor. Internally serializes with engineLock and guarantees the engine is stopped before any graph mutation to avoid AVAudioEngine assertions. Throws if the engine fails to start after rebuild so callers can handle recovery.
    public func resetGraph() throws {
        assertOnMainThread()
        // Rebuild the audio graph safely. This method guarantees the engine is stopped
        // before any graph mutations per AVAudioEngine threading rules.
        engineLock.lock()
        defer { engineLock.unlock() }

        // Cancel any active ramps to avoid concurrent volume updates
        cancelAllRamps()

        // Stop player nodes first
        playerA.stop()
        playerB.stop()

        // Ensure engine is fully stopped before touching the graph
        stopEngineLocked()
        assertEngineStoppedLocked()

        // Now it is safe to reset and rewire the graph
        engine.reset()
        engine.disconnectNodeOutput(playerA)
        engine.disconnectNodeOutput(playerB)
        engine.disconnectNodeOutput(mixerA)
        engine.disconnectNodeOutput(mixerB)
        engine.detach(playerA)
        engine.detach(playerB)
        engine.detach(mixerA)
        engine.detach(mixerB)

        // Recreate player nodes (mixers are retained and reattached)
        playerA = AVAudioPlayerNode()
        playerB = AVAudioPlayerNode()
        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(mixerA)
        engine.attach(mixerB)

        engine.connect(playerA, to: mixerA, format: nil)
        engine.connect(mixerA, to: engine.mainMixerNode, format: nil)
        engine.connect(playerB, to: mixerB, format: nil)
        engine.connect(mixerB, to: engine.mainMixerNode, format: nil)

        // Reset crossfade/player tracking state after graph rebuild.
        currentIsA = true
        mixerA.volume = 0
        mixerB.volume = 0

        engine.prepare()
        do {
            try engine.start()
        } catch {
            // Surface engine start failures to the caller to enable proper recovery.
            throw GraphError.engineStartFailed(error)
        }
    }

    /// Schedules a file on the current player after validating its format.
    /// - Throws: `GraphError.incompatibleFormat` if the file format is not supported.
    public func scheduleFileValidated(_ file: AVAudioFile, onCurrentAt time: AVAudioTime? = nil, completion: (() -> Void)? = nil) throws {
        assertOnMainThread()
        try validateFileFormat(file)
        currentPlayer.stop()
        currentPlayer.scheduleFile(file, at: time, completionHandler: completion)
    }

    /// Schedules a file on the next player after validating its format.
    /// - Throws: `GraphError.incompatibleFormat` if the file format is not supported.
    public func scheduleFileOnNextValidated(_ file: AVAudioFile, at time: AVAudioTime?) throws {
        assertOnMainThread()
        try validateFileFormat(file)
        nextPlayer.stop()
        nextPlayer.scheduleFile(file, at: time, completionHandler: nil)
    }

    public func scheduleFile(_ file: AVAudioFile, onCurrentAt time: AVAudioTime? = nil, completion: (() -> Void)? = nil) {
        assertOnMainThread()
        do {
            try scheduleFileValidated(file, onCurrentAt: time, completion: completion)
        } catch {
            print("AudioGraph scheduleFile: format validation failed — \(error)")
        }
    }

    public func scheduleFileOnNext(_ file: AVAudioFile, at time: AVAudioTime?) {
        assertOnMainThread()
        do {
            try scheduleFileOnNextValidated(file, at: time)
        } catch {
            print("AudioGraph scheduleFileOnNext: format validation failed — \(error)")
        }
    }

    public func playCurrent() {
        assertOnMainThread()
        currentPlayer.play()
    }
    public func playNext() {
        assertOnMainThread()
        nextPlayer.play()
    }

    /// Flips playback to the provided file on the alternate path.
    /// Behavior:
    /// - Validates and schedules `newCurrentFile` on the next path.
    /// - Starts the next player at zero volume, then toggles paths so it becomes current.
    /// - Sets the new current mixer to 1.0 and the new next mixer to 0.0.
    /// - This is an immediate switch (no timed crossfade). Use `ramp(mixer:to:duration:)` if you need a smooth crossfade.
    public func flipToNext(with newCurrentFile: AVAudioFile) {
        assertOnMainThread()
        // Validate and schedule the incoming file on the next path first.
        do {
            try scheduleFileOnNextValidated(newCurrentFile, at: nil)
        } catch {
            print("AudioGraph flipToNext: format validation failed — \(error)")
            return
        }

        // Make local references to avoid confusion after toggling state.
        let oldNextMixer = nextMixer
        let oldNextPlayer = nextPlayer

        // Stop the current player and ensure engine is running before starting next.
        currentPlayer.stop()
        do { try ensureStarted() } catch { print("AudioGraph flipToNext: ensureStarted failed — \(error)") }

        // Start next path at zero volume, then flip the roles.
        oldNextMixer.volume = 0
        oldNextPlayer.play()

        // Toggle which path is considered current.
        currentIsA.toggle()

        // After toggling, `currentMixer` refers to the previously-next mixer.
        currentMixer.volume = 1
        nextMixer.volume = 0
    }

    public func setCurrentPathVolume(_ v: Float) {
        assertOnMainThread()
        currentMixer.volume = v
    }
    public func setNextPathVolume(_ v: Float) {
        assertOnMainThread()
        nextMixer.volume = v
    }

    /// Smoothly ramps `mixer.volume` to `target` over `duration` seconds.
    /// Threading: This method is `@MainActor`, but updates `mixer.volume` directly from the internal `rampQueue` timer without hopping to the main queue.
    /// Ensure this aligns with your threading guarantees for AVAudioMixerNode or adopt manual rendering if stricter control is required.
    public func ramp(mixer: AVAudioMixerNode, to target: Float, duration: TimeInterval) {
        assertOnMainThread()
        let d = max(0.05, min(duration, 10.0))
        let id = ObjectIdentifier(mixer)

        // Cancel and remove any existing timer for this mixer before starting a new one
        rampQueue.sync {
            if let existing = rampTimers[id] {
                existing.setEventHandler(handler: {})
                existing.cancel()
                rampTimers[id] = nil
            }
        }

        let startVol = mixer.volume
        let delta = target - startVol
        if abs(delta) < 0.0001 {
            mixer.volume = target
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: rampQueue)
        let start = DispatchTime.now()

        // Ensure the timer always cleans itself up from the dictionary when cancelled (on rampQueue)
        timer.setCancelHandler { [weak self] in
            self?.rampQueue.async { [weak self] in
                self?.rampTimers[id] = nil
            }
        }

        timer.setEventHandler { [weak mixer, weak timer] in
            let now = DispatchTime.now()
            let elapsed = Double(now.uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000_000

            // If ramp duration reached or exceeded, set final volume and cancel the timer
            if elapsed >= d {
                if let m = mixer {
                    m.volume = target
                }
                // Cancel regardless of self's lifetime to stop the timer
                timer?.cancel()
                return
            }

            // Update volume progressively if mixer still exists
            if let m = mixer {
                let p = Float(elapsed / d)
                let newVol = startVol + delta * p
                m.volume = newVol
            }
        }

        timer.schedule(deadline: .now(), repeating: .milliseconds(6), leeway: .milliseconds(1))
        timer.resume()

        rampQueue.sync { rampTimers[id] = timer }
    }

    public var outputLatency: TimeInterval {
        engine.outputNode.presentationLatency
    }

    public func playerTime() -> (sampleTime: AVAudioFramePosition, sampleRate: Double)? {
        guard let nodeTime = currentPlayer.lastRenderTime,
              let p = currentPlayer.playerTime(forNodeTime: nodeTime) else { return nil }
        return (sampleTime: AVAudioFramePosition(p.sampleTime), sampleRate: p.sampleRate)
    }
}
