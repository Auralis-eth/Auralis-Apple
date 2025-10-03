import Foundation
import AVFoundation

@MainActor
public final class CrossfadeCoordinator {
    private let graph: AudioGraph
    private var startTimer: DispatchSourceTimer?
    private var flipTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "crossfade.coordinator", qos: .userInitiated)

    public init(graph: AudioGraph) { self.graph = graph }

    public func cancel() {
        startTimer?.cancel(); startTimer = nil
        flipTimer?.cancel(); flipTimer = nil
    }

    public func scheduleCrossfade(currentFile: AVAudioFile,
                                  nextFile: AVAudioFile,
                                  overlap: TimeInterval,
                                  startDelay: TimeInterval,
                                  peakGain: Float = 0.9) {
        cancel()
        // Compute host times
        let startHost = mach_absolute_time() &+ AVAudioTime.hostTime(forSeconds: max(0, startDelay))
        let flipHost = startHost &+ AVAudioTime.hostTime(forSeconds: max(0.05, overlap))

        // Pre-roll next
        let startTime = AVAudioTime(hostTime: startHost)
        graph.setNextPathVolume(0.0)
        graph.scheduleFileOnNext(nextFile, at: startTime)
        graph.playNext()

        // Schedule start of fade
        let st = DispatchSource.makeTimerSource(queue: queue)
        st.schedule(deadline: .init(uptimeNanoseconds: startHost), leeway: .milliseconds(1))
        st.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.graph.ramp(mixer: self.graph.currentMixer, to: 0.0, duration: overlap)
                self.graph.ramp(mixer: self.graph.nextMixer, to: peakGain, duration: overlap)
            }
        }
        st.resume()
        startTimer = st

        let ft = DispatchSource.makeTimerSource(queue: queue)
        ft.schedule(deadline: .init(uptimeNanoseconds: flipHost), leeway: .milliseconds(1))
        ft.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.graph.flipToNext(with: nextFile)
            }
        }
        ft.resume();
        flipTimer = ft
    }
}
