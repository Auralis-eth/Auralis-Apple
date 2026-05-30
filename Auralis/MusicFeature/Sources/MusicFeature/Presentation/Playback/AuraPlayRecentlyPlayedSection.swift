import AuraUI
import SwiftUI

struct AuraPlayRecentlyPlayedSection<Player: AuraPlayPlaybackPresenting>: View {
    let player: Player
    private let initialLimit = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @State private var isClearing = false
    @ScaledMetric(relativeTo: .body) private var emptyStateIconSize: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var miniCardWidth: CGFloat = 160

    private var items: [AuraPlayRecentlyPlayedItem] {
        player.auraPlayRecentlyPlayed(limit: initialLimit)
    }

    private var haptics: AuraHaptics {
        AuraHaptics(accessibilityReduceMotion: accessibilityReduceMotion)
    }

    private var emptyStateBackground: AnyShapeStyle {
        accessibilityReduceTransparency ? AnyShapeStyle(Color.surface) : AnyShapeStyle(.ultraThinMaterial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recently Played")
                    .font(.headline)
                Spacer()
                if !items.isEmpty {
                    Button("Clear All") {
                        isClearing = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .accessibilityLabel(String(localized: "Clear all recently played"))
                }
            }

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: min(emptyStateIconSize, 56)))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Nothing here yet. Play something and it will show up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(emptyStateBackground, in: RoundedRectangle(cornerRadius: 12))
            } else {
                if dynamicTypeSize.isAccessibilitySize {
                    LazyVStack(spacing: 12) {
                        ForEach(items, id: \.id) { item in
                            recentlyPlayedCard(for: item)
                        }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(items, id: \.id) { item in
                                recentlyPlayedCard(for: item)
                                    .frame(width: min(miniCardWidth, 220))
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Recently Played, \(items.count) items"))
        .confirmationDialog(
            "Clear all recently played items?",
            isPresented: $isClearing,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                player.auraPlayClearRecentlyPlayed()
                impact()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func startOverTapped(item: AuraPlayRecentlyPlayedItem) {
        impact()
        Task {
            if player.auraPlayCurrentTrack?.id == item.id {
                try? player.auraPlaySeek(to: 0)
                try? player.auraPlayPlay()
            } else {
                try? await player.auraPlayPlayRecentlyPlayed(id: item.id)
            }
        }
    }

    private func playTapped(item: AuraPlayRecentlyPlayedItem) {
        impact()
        Task {
            if player.auraPlayCurrentTrack?.id == item.id {
                try? player.auraPlayResume()
            } else {
                try? await player.auraPlayPlayRecentlyPlayed(id: item.id)
            }
        }
    }

    private func impact() {
        haptics.impact(.light)
    }

    private func recentlyPlayedCard(for item: AuraPlayRecentlyPlayedItem) -> some View {
        AuraPlayRecentlyPlayedMiniCard(item: item) {
            playTapped(item: item)
        }
        .accessibilityAction(named: String(localized: "Play")) {
            playTapped(item: item)
        }
        .accessibilityAction(named: String(localized: "Start over")) {
            startOverTapped(item: item)
        }
        .accessibilityAction(named: String(localized: "Remove from Recently Played")) {
            player.auraPlayRemoveRecentlyPlayed(id: item.id)
        }
        .contextMenu {
            Button {
                playTapped(item: item)
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                startOverTapped(item: item)
            } label: {
                Label("Start Over", systemImage: "arrow.counterclockwise")
            }

            Button(role: .destructive) {
                player.auraPlayRemoveRecentlyPlayed(id: item.id)
            } label: {
                Label("Remove from Recently Played", systemImage: "trash")
            }
        }
    }
}

private struct AuraPlayRecentlyPlayedMiniCard: View {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    let item: AuraPlayRecentlyPlayedItem
    let onTap: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var artworkHeight: CGFloat = 120

    private var boundedArtworkHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 96 : min(artworkHeight, 180)
    }

    private func relativeDescription(for date: Date?) -> String {
        guard let date else { return "Recently played" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let source = item.imageURLString,
                       let url = URL(string: source) {
                        CachedAsyncImage(url: url, mediaAccessibility: .decorative)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(height: boundedArtworkHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.25))
                            .frame(height: boundedArtworkHeight)
                            .overlay {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.gray)
                                    .accessibilityHidden(true)
                            }
                            .accessibilityHidden(true)
                    }
                    Image(systemName: "play.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(radius: 2)
                        .padding(8)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                    if let artist = item.artist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let lastPlayed = item.lastPlayed {
                        Text(lastPlayed, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Recently played")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(String(localized: "Double-tap to play"))
    }

    private var accessibilityLabel: String {
        let title = item.title
        let played = relativeDescription(for: item.lastPlayed)
        if let artist = item.artist, !artist.isEmpty {
            return String(localized: "\(title), \(artist), \(played)")
        }
        return String(localized: "\(title), \(played)")
    }
}
