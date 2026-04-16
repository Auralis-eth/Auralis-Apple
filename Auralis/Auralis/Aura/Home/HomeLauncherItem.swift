struct HomeLauncherItem: Equatable, Identifiable {
    let action: HomeLauncherAction
    let title: String
    let subtitle: String
    let badgeTitle: String
    let systemImage: String
    let buttonTitle: String
    let isPinned: Bool

    var id: String { title }
}
