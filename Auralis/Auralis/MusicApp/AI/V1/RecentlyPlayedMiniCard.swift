import SwiftUI

struct RecentlyPlayedMiniCard: View {
    let nft: NFT
    let lastPlayed: Date?
    let onTap: () -> Void

    private func relativeDescription(for date: Date?) -> String {
        guard let date else { return NSLocalizedString("Recently played", comment: "Fallback relative time") }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let s = (nft.image?.thumbnailUrl ?? nft.image?.originalUrl), let url = URL(string: s) {
                        CachedAsyncImage(url: url)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.25))
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "music.note").foregroundStyle(.gray)
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
                    Text(nft.name ?? NSLocalizedString("Unknown Track", comment: "Unknown track title"))
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
                        Text(NSLocalizedString("Recently played", comment: "Fallback relative time"))
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
        .accessibilityLabel({ () -> Text in
            let title = nft.name ?? NSLocalizedString("Unknown Track", comment: "Unknown track title")
            let artist = nft.artistName
            let played = relativeDescription(for: lastPlayed)
            if let artist, !artist.isEmpty {
                return Text("\(title), \(artist), \(played)")
            } else {
                return Text("\(title), \(played)")
            }
        }())
        .accessibilityHint(Text(NSLocalizedString("Double-tap to play", comment: "Hint to play recently played item")))
    }
}
