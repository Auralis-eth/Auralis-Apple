import AuralisPrimaryModels
import SwiftData

public enum AuraPlaySchema {
    public static var models: [any PersistentModel.Type] {
        [
            AuraPlayNFTToken.self,
            AuraPlayMediaItem.self,
            AuraPlayMediaEmbedding.self,
            AuraPlayPlaybackPositionState.self,
            AuraPlayPlaybackPositionTombstone.self,
            AuraPlayPlaylist.self,
            AuraPlayPlaylistItem.self,
        ]
    }
}
