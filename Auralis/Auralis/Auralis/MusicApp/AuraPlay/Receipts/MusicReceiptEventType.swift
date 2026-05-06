import Foundation

enum MusicReceiptEventType: String, Sendable {
    case mediaClassified = "music.media_classified"
    case playlistCreated = "music.playlist.created"
    case playlistModified = "music.playlist.modified"
    case metadataOverrideApplied = "music.metadata_override.applied"
    case queueChanged = "music.queue.changed"
    case playbackStarted = "music.playback.started"
    case playbackCompleted = "music.playback.completed"
    case autoOrganizationRun = "music.auto_organization.run"
    case backgroundMusicTaskRun = "music.background_task.run"
    case exportCreated = "music.export.created"
    case policyBlocked = "music.policy.blocked"

    var summary: String {
        switch self {
        case .mediaClassified:
            return "Classified music media"
        case .playlistCreated:
            return "Created playlist"
        case .playlistModified:
            return "Updated playlist"
        case .metadataOverrideApplied:
            return "Applied metadata override"
        case .queueChanged:
            return "Changed playback queue"
        case .playbackStarted:
            return "Started playback"
        case .playbackCompleted:
            return "Completed playback"
        case .autoOrganizationRun:
            return "Ran auto-organization"
        case .backgroundMusicTaskRun:
            return "Ran background music task"
        case .exportCreated:
            return "Created music export"
        case .policyBlocked:
            return "Blocked music action by policy"
        }
    }

    var scope: String {
        switch self {
        case .playlistCreated, .playlistModified:
            return "music.playlist"
        case .queueChanged, .playbackStarted, .playbackCompleted:
            return "music.playback"
        case .mediaClassified, .metadataOverrideApplied, .autoOrganizationRun:
            return "music.library"
        case .backgroundMusicTaskRun:
            return "music.background"
        case .exportCreated:
            return "music.export"
        case .policyBlocked:
            return "music.policy"
        }
    }
}
