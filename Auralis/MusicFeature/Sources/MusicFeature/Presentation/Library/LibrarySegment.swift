import Foundation

public enum LibrarySegment: String, CaseIterable, Identifiable {
    case all
    case audio
    case video
    case collections
    case creators
    case playlists

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .audio: "Audio"
        case .video: "Video"
        case .collections: "Collections"
        case .creators: "Creators"
        case .playlists: "Playlists"
        }
    }
}

public enum LibraryLayoutMode: String, CaseIterable, Identifiable {
    case grid
    case list

    public var id: String { rawValue }
}

