import Foundation

public enum AuraPlayIntelligenceSettings {
    public static let smartShuffleEnabledDefaultsKey = "auraplay.intelligence.smartShuffle.enabled"

    /// Broad semantic threshold for prompt-generated playlists. Playlist Playground
    /// deliberately pulls a larger pool, then samples from it, so this stays looser
    /// than the item-to-item recommendation threshold.
    public static let defaultSemanticMinimumScore: Float = 0.18

    /// Strict More Like This threshold. If this produces too few matches, the
    /// recommendation service retries once with the relaxed threshold below.
    public static let recommendationStrictMinimumScore: Float = 0.72
    public static let recommendationRelaxedMinimumScore: Float = 0.60
    public static let recommendationRelaxationMinimumResultCount = 3
}
