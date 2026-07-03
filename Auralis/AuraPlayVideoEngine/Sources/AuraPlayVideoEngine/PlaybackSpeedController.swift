import AVFoundation
import Foundation

public enum PlaybackSpeedOption: Double, CaseIterable, Identifiable, Sendable {
    case half = 0.5
    case threeQuarter = 0.75
    case normal = 1.0
    case oneQuarter = 1.25
    case oneHalf = 1.5
    case double = 2.0

    public init(storedRawValue: Double) {
        self = Self(rawValue: storedRawValue) ?? .normal
    }

    public var id: Double { rawValue }

    public var displayLabel: String {
        switch self {
        case .half:
            "0.5x"
        case .threeQuarter:
            "0.75x"
        case .normal:
            "1x"
        case .oneQuarter:
            "1.25x"
        case .oneHalf:
            "1.5x"
        case .double:
            "2x"
        }
    }

    public var pitchAlgorithm: AVAudioTimePitchAlgorithm {
        rawValue < 1 ? .timeDomain : .spectral
    }
}

@MainActor
public struct PlaybackSpeedController {
    public static let preferenceKey = "com.auraplay.videoPlaybackSpeed"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var storedSpeed: PlaybackSpeedOption {
        let value = userDefaults.double(forKey: Self.preferenceKey)
        guard value > 0 else { return .normal }
        return PlaybackSpeedOption(storedRawValue: value)
    }

    public func setSpeed(_ speed: PlaybackSpeedOption, on player: AVPlayer, persist: Bool = true) throws {
        guard let item = player.currentItem else {
            throw VideoPlaybackError.noCurrentItem
        }

        item.audioTimePitchAlgorithm = speed.pitchAlgorithm
        if persist {
            userDefaults.set(speed.rawValue, forKey: Self.preferenceKey)
        }
        player.rate = Float(speed.rawValue)
    }

    public func applyStoredSpeed(on player: AVPlayer) throws {
        try setSpeed(storedSpeed, on: player, persist: false)
    }
}
