import Foundation

public enum AuraPlayAudioSettings {
    public static let eqPresetDefaultsKey = "com.auraplay.eqPreset"
    public static let normalizationEnabledDefaultsKey = "com.auraplay.normalizationEnabled"
    public static let crossfadeDurationDefaultsKey = "com.auraplay.crossfadeDuration"
    public static let customEQGainsDefaultsKey = "com.auraplay.customEQGains"
    public static let downloadForOfflineDefaultsKey = "com.auraplay.downloadForOffline"

    public static let bandCenters: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    public static let defaultCustomEQGains = Array(repeating: Float(0), count: bandCenters.count)
    public static let minimumBandGain: Float = -12
    public static let maximumBandGain: Float = 12

    public static func eqPreset(from defaults: UserDefaults = .standard) -> AuraPlayEQPresetID {
        AuraPlayEQPresetID(rawValue: defaults.string(forKey: eqPresetDefaultsKey) ?? AuraPlayEQPresetID.flat.rawValue) ?? .flat
    }

    public static func normalizationEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: normalizationEnabledDefaultsKey) as? Bool ?? true
    }

    public static func downloadForOfflineEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: downloadForOfflineDefaultsKey) as? Bool ?? false
    }

    public static func crossfadeDuration(from defaults: UserDefaults = .standard) -> Double {
        min(8, max(0, defaults.double(forKey: crossfadeDurationDefaultsKey).rounded()))
    }

    public static func customEQGains(from defaults: UserDefaults = .standard) -> [Float] {
        if let storedGains = defaults.array(forKey: customEQGainsDefaultsKey) as? [Double] {
            return normalizedCustomEQGains(storedGains.map(Float.init))
        }

        if let storedGains = defaults.array(forKey: customEQGainsDefaultsKey) as? [Float] {
            return normalizedCustomEQGains(storedGains)
        }

        return defaultCustomEQGains
    }

    public static func writeCustomEQGains(_ gains: [Float], to defaults: UserDefaults = .standard) {
        let normalizedGains = normalizedCustomEQGains(gains).map(Double.init)
        defaults.set(normalizedGains, forKey: customEQGainsDefaultsKey)
    }

    public static func normalizedCustomEQGains(_ gains: [Float]) -> [Float] {
        let clampedGains = gains.prefix(bandCenters.count).map { min(max($0, minimumBandGain), maximumBandGain) }
        if clampedGains.count == bandCenters.count {
            return clampedGains
        }

        return clampedGains + Array(repeating: 0, count: bandCenters.count - clampedGains.count)
    }

    public static func bandLabel(for center: Float) -> String {
        if center >= 1_000 {
            return "\(Int(center / 1_000)) kHz"
        }

        return "\(Int(center)) Hz"
    }
}
