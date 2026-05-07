import AuralisPrimaryModels
import SwiftUI

struct AuraPlayRecentlyPlayedSection: View {
    @ObservedObject var audioEngine: AudioEngine
    private let initialLimit = 20
    @State private var isClearing = false

    private var items: [NFT] {
        audioEngine.getRecentlyPlayed(limit: initialLimit)
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
                    .accessibilityLabel("Clear all recently played")
                }
            }

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Nothing here yet. Play something and it will show up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.id) { nft in
                            AuraPlayRecentlyPlayedMiniCard(
                                nft: nft,
                                lastPlayed: audioEngine.lastPlayedDate(for: nft.id)
                            ) {
                                playTapped(nft: nft)
                            }
                            .frame(width: 160)
                            .contextMenu {
                                Button {
                                    playTapped(nft: nft)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }

                                Button {
                                    startOverTapped(nft: nft)
                                } label: {
                                    Label("Start Over", systemImage: "arrow.counterclockwise")
                                }

                                Button(role: .destructive) {
                                    audioEngine.removeFromPrevious(id: nft.id)
                                } label: {
                                    Label("Remove from Recently Played", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recently Played, \(items.count) items")
        .confirmationDialog(
            "Clear all recently played items?",
            isPresented: $isClearing,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                audioEngine.clearPreviousHistory()
                impact()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func startOverTapped(nft: NFT) {
        impact()
        Task {
            if audioEngine.currentTrackNFTID == nft.id {
                try? audioEngine.seek(to: 0)
                try? audioEngine.play()
            } else {
                try? await audioEngine.loadAndPlay(nft: nft)
            }
        }
    }

    private func playTapped(nft: NFT) {
        impact()
        Task {
            if audioEngine.currentTrackNFTID == nft.id {
                try? audioEngine.resume()
            } else {
                try? await audioEngine.loadAndPlay(nft: nft)
            }
        }
    }

    private func impact() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

private struct AuraPlayRecentlyPlayedMiniCard: View {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    let nft: NFT
    let lastPlayed: Date?
    let onTap: () -> Void

    private func relativeDescription(for date: Date?) -> String {
        guard let date else { return "Recently played" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let source = nft.image?.thumbnailUrl ?? nft.image?.originalUrl,
                       let url = URL(string: source) {
                        CachedAsyncImage(url: url)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.25))
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.gray)
                            }
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
                    Text(nft.name ?? "Unknown Track")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    if let artist = nft.artistName, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let lastPlayed {
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
        .accessibilityHint("Double-tap to play")
    }

    private var accessibilityLabel: String {
        let title = nft.name ?? "Unknown Track"
        let played = relativeDescription(for: lastPlayed)
        if let artist = nft.artistName, !artist.isEmpty {
            return "\(title), \(artist), \(played)"
        }
        return "\(title), \(played)"
    }
}
