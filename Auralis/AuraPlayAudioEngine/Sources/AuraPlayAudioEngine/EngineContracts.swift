import AVFoundation
import Foundation

public enum TransitionQuality: Equatable, Sendable {
    case gapless
    case briefGap
}

public enum EngineRecoveryEvent: Equatable, Sendable {
    case paused(reason: EnginePauseReason)
    case configurationChanged(resumeFrame: AVAudioFramePositionValue)
    case interruptionRestored(shouldResume: Bool, resumeFrame: AVAudioFramePositionValue)
    case buffering(mediaID: String, frame: AVAudioFramePositionValue)
    case recovered(mediaID: String, frame: AVAudioFramePositionValue)
    case failed(AuraPlayError)
}

public enum EnginePauseReason: String, Equatable, Sendable {
    case routeUnavailable
    case interruptionBegan
}

public typealias AVAudioFramePositionValue = Int64

public protocol AudioEngineControlling: Sendable {
    func start() async throws
    func stop() async
    func pause() async
    func resume() async throws
}

public protocol GaplessScheduling: Sendable {
    func scheduleCurrent(fileURL: URL, startingFrame: AVAudioFramePositionValue) async throws
    func prepareNext<M: AuraPlayableMedia>(_ media: M) async throws -> TransitionQuality
}

public struct AudioVisualizationChannelLevel: Equatable, Sendable {
    public let rms: Float
    public let peak: Float

    public init(rms: Float, peak: Float) {
        self.rms = rms
        self.peak = peak
    }
}

public struct AudioVisualizationFrame: Equatable, Sendable {
    public let renderFrame: AVAudioFramePositionValue?
    public let hostTime: UInt64?
    public let sampleRate: Double
    public let frameCount: AVAudioFrameCount
    public let channels: [AudioVisualizationChannelLevel]

    public init(
        renderFrame: AVAudioFramePositionValue?,
        hostTime: UInt64?,
        sampleRate: Double,
        frameCount: AVAudioFrameCount,
        channels: [AudioVisualizationChannelLevel]
    ) {
        self.renderFrame = renderFrame
        self.hostTime = hostTime
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.channels = channels
    }
}

public struct AudioVisualizationConfiguration: Equatable, Sendable {
    public let framesPerSecond: Double
    public let preferredBufferFrameCount: AVAudioFrameCount?

    public init(framesPerSecond: Double = 30, preferredBufferFrameCount: AVAudioFrameCount? = nil) {
        self.framesPerSecond = min(max(framesPerSecond, 1), 60)
        self.preferredBufferFrameCount = preferredBufferFrameCount
    }

    public func bufferFrameCount(sampleRate: Double) -> AVAudioFrameCount {
        if let preferredBufferFrameCount {
            return min(max(preferredBufferFrameCount, 256), 16_384)
        }
        return AVAudioFrameCount(min(max(sampleRate / framesPerSecond, 256), 16_384))
    }
}

public protocol AudioVisualizationPublishing: Sendable {
    func startVisualization(configuration: AudioVisualizationConfiguration) -> AsyncStream<AudioVisualizationFrame>
    func stopVisualization() async
}

public enum AudioVisualizationAnalyzer {
    public static func makeFrame(buffer: AVAudioPCMBuffer, time: AVAudioTime) -> AudioVisualizationFrame {
        AudioVisualizationFrame(
            renderFrame: time.isSampleTimeValid ? AVAudioFramePositionValue(time.sampleTime) : nil,
            hostTime: time.isHostTimeValid ? time.hostTime : nil,
            sampleRate: buffer.format.sampleRate,
            frameCount: buffer.frameLength,
            channels: channelLevels(buffer: buffer)
        )
    }

    public static func channelLevels(buffer: AVAudioPCMBuffer) -> [AudioVisualizationChannelLevel] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return []
        }

        return (0..<Int(buffer.format.channelCount)).map { channel in
            let samples = channelData[channel]
            var sumOfSquares = Float(0)
            var peak = Float(0)

            for frame in 0..<frameCount {
                let sample = samples[frame]
                sumOfSquares += sample * sample
                peak = max(peak, abs(sample))
            }

            let rms = sqrt(sumOfSquares / Float(frameCount))
            return AudioVisualizationChannelLevel(rms: rms, peak: peak)
        }
    }
}

public struct EngineGraphDescription: Equatable, Sendable {
    public let customNodeNames: [String]
    public let sampleRate: Double
    public let channelCount: Int
    public let connectionCount: Int
    public let containsEnvironmentNode: Bool

    public init(
        customNodeNames: [String],
        sampleRate: Double,
        channelCount: Int,
        connectionCount: Int,
        containsEnvironmentNode: Bool
    ) {
        self.customNodeNames = customNodeNames
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.connectionCount = connectionCount
        self.containsEnvironmentNode = containsEnvironmentNode
    }
}
