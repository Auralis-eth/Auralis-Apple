import Foundation

enum AuraPlayErrorPresentationContext {
    case librarySync
    case librarySummary
    case playlistMutation
    case playlistGeneration
    case playlistSave
    case recommendation
    case search
    case artwork
    case playback
}

enum AuraPlayErrorPresentation {
    static func message(for error: Error, context: AuraPlayErrorPresentationContext) -> String {
        switch context {
        case .librarySync:
            return "AuraPlay could not sync NFT discovery for this wallet yet. Please try again."
        case .librarySummary:
            return "AuraPlay could not refresh the music library yet. Please try again."
        case .playlistMutation:
            return "AuraPlay could not update this playlist. Please try again."
        case .playlistGeneration:
            return "Playlist generation is unavailable right now."
        case .playlistSave:
            return "AuraPlay could not save this playlist. Please try again."
        case .recommendation:
            return "AuraPlay could not load recommendations right now."
        case .search:
            return "AuraPlay search is unavailable right now. Please try again."
        case .artwork:
            return "AuraPlay could not load artwork for the active track."
        case .playback:
            return "AuraPlay could not read playback state cleanly. Please try again."
        }
    }

    static func message(for error: AuraPlayError, context: AuraPlayErrorPresentationContext) -> String {
        message(for: error as Error, context: context)
    }
}
