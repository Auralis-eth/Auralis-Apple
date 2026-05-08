/// Registry of canonical capabilities and their metadata.
public enum CapabilityRegistry {
    public static let descriptors: [CapabilityID: CapabilityDescriptor] = [
        .signMessage: CapabilityDescriptor(
            id: .signMessage,
            category: .wallet,
            title: "Sign Message",
            summary: "Create a wallet signature for an arbitrary message."
        ),
        .approveSpending: CapabilityDescriptor(
            id: .approveSpending,
            category: .wallet,
            title: "Approve Spending",
            summary: "Approve token spending permissions."
        ),
        .draftTransaction: CapabilityDescriptor(
            id: .draftTransaction,
            category: .wallet,
            title: "Draft Transaction",
            summary: "Prepare a transaction for later execution."
        ),
        .runPlugin: CapabilityDescriptor(
            id: .runPlugin,
            category: .plugin,
            title: "Run Plugin",
            summary: "Run a tool or plugin workflow."
        ),
        .playlistManagement: CapabilityDescriptor(
            id: .playlistManagement,
            category: .music,
            title: "Playlist Management",
            summary: "Create or modify music playlists."
        ),
        .autoOrganization: CapabilityDescriptor(
            id: .autoOrganization,
            category: .music,
            title: "Auto Organization",
            summary: "Suggest or apply music library organization."
        ),
        .musicLibraryClassification: CapabilityDescriptor(
            id: .musicLibraryClassification,
            category: .music,
            title: "Music Library Classification",
            summary: "Classify media in the music library."
        ),
        .metadataOverride: CapabilityDescriptor(
            id: .metadataOverride,
            category: .music,
            title: "Metadata Override",
            summary: "Apply user or system metadata corrections."
        ),
        .backgroundMusicTask: CapabilityDescriptor(
            id: .backgroundMusicTask,
            category: .music,
            title: "Background Music Task",
            summary: "Run a background task over music library data."
        ),
        .musicExport: CapabilityDescriptor(
            id: .musicExport,
            category: .music,
            title: "Music Export",
            summary: "Create an export from music library data."
        ),
        .playbackQueue: CapabilityDescriptor(
            id: .playbackQueue,
            category: .playback,
            title: "Playback Queue",
            summary: "Change the active playback queue."
        ),
        .audioPlayback: CapabilityDescriptor(
            id: .audioPlayback,
            category: .playback,
            title: "Audio Playback",
            summary: "Start or complete audio playback."
        ),
    ]

    public static func descriptor(for id: CapabilityID) -> CapabilityDescriptor {
        descriptors[id] ?? CapabilityDescriptor(
            id: id,
            category: .plugin,
            title: id.rawValue,
            summary: id.rawValue
        )
    }
}
