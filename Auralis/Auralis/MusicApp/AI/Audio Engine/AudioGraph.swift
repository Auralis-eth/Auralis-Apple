import Foundation
import AVFoundation

@MainActor
public final class AudioGraph {
    public enum GraphError: Error { case engineStartFailed(Error), fileLoadFailed(Error) }

    private let engine = AVAudioEngine()
    private var playerA = AVAudioPlayerNode()
    private var playerB = AVAudioPlayerNode()
    private let mixerA = AVAudioMixerNode()
    private let mixerB = AVAudioMixerNode()

    private var currentIsA = true
    public var currentPlayer: AVAudioPlayerNode { currentIsA ? playerA : playerB }
    public var nextPlayer: AVAudioPlayerNode { currentIsA ? playerB : playerA }
    public var currentMixer: AVAudioMixerNode { currentIsA ? mixerA : mixerB }
    public var nextMixer: AVAudioMixerNode { currentIsA ? mixerB : mixerA }

    // Ramp infra
    private let rampQueue = DispatchQueue(label: "audio.graph.ramp", qos: .userInteractive)
    private var rampTimers: [ObjectIdentifier: DispatchSourceTimer] = [:]

    public init() {
        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(mixerA)
        engine.attach(mixerB)

        let out = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(playerA, to: mixerA, format: out)
        engine.connect(mixerA, to: engine.mainMixerNode, format: out)
        engine.connect(playerB, to: mixerB, format: out)
        engine.connect(mixerB, to: engine.mainMixerNode, format: out)
        mixerA.volume = 0
        mixerB.volume = 0
        engine.prepare()
    }

    public func start() throws {
        if engine.isRunning { return }
        do { try engine.start() } catch { throw GraphError.engineStartFailed(error) }
    }

    public func ensureStarted() throws {
        if engine.isRunning { return }
        engine.prepare()
        do { try engine.start() } catch { throw GraphError.engineStartFailed(error) }
    }

    public func stop() {
        playerA.stop()
        playerB.stop()
        mixerA.volume = 0
        mixerB.volume = 0
        engine.pause()
        engine.stop()
    }

    public func resetGraph() {
        playerA.stop()
        playerB.stop()
        engine.stop()
        engine.reset()
        engine.disconnectNodeOutput(playerA)
        engine.disconnectNodeOutput(playerB)
        engine.disconnectNodeOutput(mixerA)
        engine.disconnectNodeOutput(mixerB)
        engine.detach(playerA)
        engine.detach(playerB)
        engine.detach(mixerA)
        engine.detach(mixerB)
        playerA = AVAudioPlayerNode()
        playerB = AVAudioPlayerNode()
        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(mixerA)
        engine.attach(mixerB)
        let out = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(playerA, to: mixerA, format: out)
        engine.connect(mixerA, to: engine.mainMixerNode, format: out)
        engine.connect(playerB, to: mixerB, format: out)
        engine.connect(mixerB, to: engine.mainMixerNode, format: out)
        engine.prepare()
        try? engine.start()
    }

    public func scheduleFile(_ file: AVAudioFile, onCurrentAt time: AVAudioTime? = nil, completion: (() -> Void)? = nil) {
        currentPlayer.stop()
        currentPlayer.scheduleFile(file, at: time, completionHandler: completion)
    }

    public func scheduleFileOnNext(_ file: AVAudioFile, at time: AVAudioTime?) {
        nextPlayer.stop()
        nextPlayer.scheduleFile(file, at: time, completionHandler: nil)
    }

    public func playCurrent() {
        currentPlayer.play()
    }
    public func playNext() {
        nextPlayer.play()
    }

    public func flipToNext(with newCurrentFile: AVAudioFile) {
        currentPlayer.stop()
        currentMixer.volume = 0
        currentIsA.toggle()
        currentMixer.volume = 1
        nextMixer.volume = 0
    }

    public func setCurrentPathVolume(_ v: Float) {
        currentMixer.volume = v
    }
    public func setNextPathVolume(_ v: Float) {
        nextMixer.volume = v
    }

    public func ramp(mixer: AVAudioMixerNode, to target: Float, duration: TimeInterval) {
        let d = max(0.05, min(duration, 10.0))
        let id = ObjectIdentifier(mixer)
        rampTimers[id]?.cancel()
        rampTimers[id] = nil
        let startVol = mixer.volume
        let delta = target - startVol
        if abs(delta) < 0.0001 {
            mixer.volume = target
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: rampQueue)
        let start = DispatchTime.now()
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = DispatchTime.now()
            let elapsed = Double(now.uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000_000
            if elapsed >= d {
                DispatchQueue.main.async { mixer.volume = target }
                self.rampTimers[id]?.cancel()
                self.rampTimers[id] = nil
                return
            }
            let p = Float(elapsed / d)
            let newVol = startVol + delta * p
            DispatchQueue.main.async { mixer.volume = newVol }
        }
        timer.schedule(deadline: .now(), repeating: .milliseconds(6), leeway: .milliseconds(1))
        timer.resume()
        rampTimers[id] = timer
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
