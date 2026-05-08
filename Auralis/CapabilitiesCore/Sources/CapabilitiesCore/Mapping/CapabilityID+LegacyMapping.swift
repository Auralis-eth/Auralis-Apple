public extension CapabilityID {
    /// Normalizes older raw action/capability strings into canonical capability IDs.
    static func legacy(_ rawValue: String) -> CapabilityID? {
        switch rawValue {
        case "sign_message":
            return .signMessage
        case "approve_spending":
            return .approveSpending
        case "draft_transaction":
            return .draftTransaction
        case "run_plugin":
            return .runPlugin
        case "playlist_management":
            return .playlistManagement
        case "auto_organization":
            return .autoOrganization
        case "music_library_classification":
            return .musicLibraryClassification
        case "metadata_override":
            return .metadataOverride
        case "background_music_task":
            return .backgroundMusicTask
        case "music_export":
            return .musicExport
        case "playback_queue":
            return .playbackQueue
        case "audio_playback":
            return .audioPlayback
        default:
            return CapabilityID(rawValue: rawValue)
        }
    }
}
