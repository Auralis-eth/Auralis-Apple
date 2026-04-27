enum ReceiptActorFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case user
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Actors"
        case .user:
            return "User"
        case .system:
            return "System"
        }
    }
}
