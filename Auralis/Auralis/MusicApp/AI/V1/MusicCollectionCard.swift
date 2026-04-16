import SwiftUI

struct MusicCollectionCard: View {
    let summary: MusicCollectionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: summary.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.gray.opacity(0.25))
                    .overlay {
                        SystemImage("square.stack.3d.up")
                            .foregroundStyle(.gray)
                    }
            }
            .frame(width: 190, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 6) {
                Text(summary.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                if let subtitle = summary.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(summary.trackCountLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    if summary.hasUnavailableTracks {
                        Text("Partial")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .frame(width: 190, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
