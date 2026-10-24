/// Registry of canonical capabilities and their metadata.
public enum CapabilityRegistry {
    public static let descriptors: [CapabilityID: CapabilityDescriptor] = [
        .signMessage: .init(id: .signMessage, category: .wallet, title: "Sign Message", summary: "Create a wallet signature for an arbitrary message."),
        .approveSpending: .init(id: .approveSpending, category: .wallet, title: "Approve Spending", summary: "Approve token spending permissions."),
        .draftTransaction: .init(id: .draftTransaction, category: .wallet, title: "Draft Transaction", summary: "Prepare a transaction for later execution."),
        .runPlugin: .init(id: .runPlugin, category: .plugin, title: "Run Plugin", summary: "Run a tool or plugin workflow."),
        .playlistManagement: .init(id: .playlistManagement, category: .music, title: "Playlist Management", summary: "Create or modify music playlists."),
        .autoOrganization: .init(id: .autoOrganization, category: .music, title: "Auto Organization", summary: "Suggest or apply music library organization."),
        .musicLibraryClassification: .init(id: .musicLibraryClassification, category: .music, title: "Music Library Classification", summary: "Classify media in the music library."),
        .metadataOverride: .init(id: .metadataOverride, category: .music, title: "Metadata Override", summary: "Apply user or system metadata corrections."),
        .backgroundMusicTask: .init(id: .backgroundMusicTask, category: .music, title: "Background Music Task", summary: "Run a background task over music library data."),
        .musicExport: .init(id: .musicExport, category: .music, title: "Music Export", summary: "Create an export from music library data."),
        .playbackQueue: .init(id: .playbackQueue, category: .playback, title: "Playback Queue", summary: "Change the active playback queue."),
        .audioPlayback: .init(id: .audioPlayback, category: .playback, title: "Audio Playback", summary: "Start or complete audio playback.")
    ]

    /// Returns registered metadata, or a conservative crypto-domain fallback for unknown IDs.
    public static func descriptor(for id: CapabilityID) -> CapabilityDescriptor {
        descriptors[id] ?? CapabilityDescriptor(
            id: id,
            category: .wallet,
            title: id.rawValue,
            summary: id.rawValue
        )
    }
}
