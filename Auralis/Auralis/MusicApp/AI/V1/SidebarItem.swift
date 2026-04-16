import Foundation

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case library, playlists, downloads, settings

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .library:   return "music.note.list"
        case .playlists: return "text.badge.plus"
        case .downloads: return "arrow.down.circle"
        case .settings:  return "gearshape"
        }
    }
}
