/// Canonical identifiers for app capabilities that can appear in policy,
/// receipt, approval, and operator flows.
public enum CapabilityID: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case signMessage = "sign_message"
    case approveSpending = "approve_spending"
    case draftTransaction = "draft_transaction"
    case runPlugin = "run_plugin"
    case playlistManagement = "playlist_management"
    case autoOrganization = "auto_organization"
    case musicLibraryClassification = "music_library_classification"
    case metadataOverride = "metadata_override"
    case backgroundMusicTask = "background_music_task"
    case musicExport = "music_export"
    case playbackQueue = "playback_queue"
    case audioPlayback = "audio_playback"
}
