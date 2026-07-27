import Foundation

enum AuraPlayPlaybackPreferenceSettings {
    static let shuffleModeDefaultsKey = "com.auraplay.shuffleMode"
    static let repeatModeDefaultsKey = "com.auraplay.repeatMode"

    static func shuffleMode(from defaults: UserDefaults = .standard) -> AuraPlayShuffleMode {
        AuraPlayShuffleMode(rawValue: defaults.string(forKey: shuffleModeDefaultsKey) ?? AuraPlayShuffleMode.off.rawValue) ?? .off
    }

    static func repeatMode(from defaults: UserDefaults = .standard) -> AuraPlayRepeatMode {
        AuraPlayRepeatMode(rawValue: defaults.string(forKey: repeatModeDefaultsKey) ?? AuraPlayRepeatMode.off.rawValue) ?? .off
    }
}
