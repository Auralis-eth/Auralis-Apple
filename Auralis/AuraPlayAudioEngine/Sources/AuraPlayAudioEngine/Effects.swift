import Accelerate
import AVFoundation
import Foundation

public enum EQPreset: Equatable, Sendable {
    case flat
    case bassBoost
    case vocalClarity
    case custom([Float])

    public static let bandCenters: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    public var gains: [Float] {
        switch self {
        case .flat:
            return Array(repeating: 0, count: Self.bandCenters.count)
        case .bassBoost:
            return [4, 4, 4, 0, 0, 0, 0, 0, 0, 0]
        case .vocalClarity:
            return [-2, 0, 0, 0, 3, 3, 3, 0, 0, 0]
        case .custom(let gains):
            return Array(gains.prefix(Self.bandCenters.count)) + Array(repeating: 0, count: max(0, Self.bandCenters.count - gains.count))
        }
    }
}

public enum LoudnessNormalization {
    public static let targetApproxLUFS = -14.0
    public static let minimumGainDB = -12.0
    public static let maximumGainDB = 12.0
    public static let approximateLoudnessNote = "RMS-derived approximate loudness, not ITU-R BS.1770 LUFS."

    public static func gainDB(for approxLoudnessLUFS: Double?) -> Double {
        guard let approxLoudnessLUFS else {
            return 0
        }

        let proposedGain = targetApproxLUFS - approxLoudnessLUFS
        return min(max(proposedGain, minimumGainDB), maximumGainDB)
    }
}

public struct ApproximateLoudnessAnalyzer: Sendable {
    public init() {}

    public func measureApproxLoudnessLUFS(fileURL: URL, frameCapacity: AVAudioFrameCount = 32_768) throws -> Double {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: fileURL)
        } catch {
            throw AuraPlayError.corruptedFile(fileURL)
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCapacity) else {
            throw AuraPlayError.corruptedFile(fileURL)
        }

        var sumOfSquares = Double(0)
        var sampleCount = Double(0)

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: frameCapacity)
            guard let channelData = buffer.floatChannelData else {
                continue
            }

            let frames = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            guard frames > 0, channels > 0 else {
                continue
            }

            for channel in 0..<channels {
                var channelSum = Float(0)
                vDSP_svesq(channelData[channel], 1, &channelSum, vDSP_Length(frames))
                sumOfSquares += Double(channelSum)
                sampleCount += Double(frames)
            }
        }

        guard sampleCount > 0 else {
            throw AuraPlayError.corruptedFile(fileURL)
        }

        let rms = sqrt(sumOfSquares / sampleCount)
        guard rms > 0 else {
            return -Double.infinity
        }

        return 20 * log10(rms)
    }
}

public protocol AudioEffectsControlling: Sendable {
    func applyEQPreset(_ preset: EQPreset) async
    func configureForContentKind(_ contentKind: AuraPlayableContentKind) async
    func applyNormalizationGain(approxLoudnessLUFS: Double?) async
}
