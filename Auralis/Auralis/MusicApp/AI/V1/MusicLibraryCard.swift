import SwiftUI

struct MusicLibraryCard: View {
    let item: MusicLibraryItem

    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: item.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.25))
                    .overlay {
                        SystemImage("music.note").foregroundStyle(.gray)
                    }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)

                if let artist = item.artistName, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    SystemImage(item.availability == .ready ? "speaker.wave.2.fill" : "music.note")
                        .foregroundStyle(.blue)
                        .imageScale(.small)

                    if let ct = item.contentType, ct.hasPrefix("audio/") {
                        Text(ct.replacingOccurrences(of: "audio/", with: "").uppercased())
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if item.availability == .unavailable {
                        Text("UNAVAILABLE")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if let network = Chain(rawValue: item.networkRawValue) {
                VStack(spacing: 4) {
                    SystemImage("link")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    Text(network.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("music.card.\(item.id)")
    }
}
