import SwiftData
import SwiftUI

struct MusicCollectionDetailView: View {
    let collectionKey: String
    let collectionTitle: String
    let currentAccountAddress: String?
    let currentChain: Chain
    let onOpenItem: (String) -> Void

    @Query private var libraryItems: [MusicLibraryItem]

    init(
        collectionKey: String,
        collectionTitle: String,
        currentAccountAddress: String?,
        currentChain: Chain,
        onOpenItem: @escaping (String) -> Void
    ) {
        self.collectionKey = collectionKey
        self.collectionTitle = collectionTitle
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain
        self.onOpenItem = onOpenItem

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _libraryItems = Query(
            filter: #Predicate<MusicLibraryItem> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            },
            sort: [
                SortDescriptor(\MusicLibraryItem.normalizedArtistKey),
                SortDescriptor(\MusicLibraryItem.normalizedTitleKey),
                SortDescriptor(\MusicLibraryItem.id)
            ]
        )
    }

    private var items: [MusicLibraryItem] {
        libraryItems.filter { $0.normalizedCollectionKey == collectionKey }
    }

    private var presentation: MusicCollectionDetailPresentation {
        MusicCollectionDetailPresentation(
            summary: MusicCollectionSummary(
                key: collectionKey,
                title: collectionTitle,
                subtitle: nil,
                artworkURL: items.compactMap(\.artworkURL).first,
                trackCount: items.count,
                hasUnavailableTracks: items.contains { $0.availability == .unavailable }
            ),
            items: items,
            chain: currentChain
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(presentation.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textPrimary)

                        if let subtitle = presentation.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }

                        HStack(spacing: 10) {
                            MusicCollectionMetaChip(title: presentation.trackCountLabel, systemImage: "music.note.list")
                            MusicCollectionMetaChip(title: presentation.chainTitle, systemImage: "link")
                            if presentation.hasUnavailableTracks {
                                MusicCollectionMetaChip(title: "Partial", systemImage: "exclamationmark.triangle")
                            }
                        }

                        if let metadataStatus = presentation.metadataStatus {
                            SecondaryText(metadataStatus)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Tracks")
                        .font(.headline)

                    ForEach(items) { item in
                        Button {
                            onOpenItem(item.sourceNFTID)
                        } label: {
                            MusicCollectionTrackRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("music.collection.track.\(item.id)")
                    }
                }
            }
            .padding()
        }
        .background(Color.background)
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("music.collection.detail")
    }
}

struct MusicCollectionSummary: Equatable, Hashable {
    let key: String
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let trackCount: Int
    let hasUnavailableTracks: Bool

    var trackCountLabel: String {
        "\(trackCount) track" + (trackCount == 1 ? "" : "s")
    }

    static func summaries(from items: [MusicLibraryItem]) -> [MusicCollectionSummary] {
        let grouped = Dictionary(grouping: items) { item in
            cleanedKey(item.normalizedCollectionKey) ?? "__ungrouped__"
        }

        return grouped.compactMap { key, group in
            guard let baseItem = group.first else {
                return nil
            }

            let title = cleanedText(baseItem.collectionName)
                ?? cleanedText(baseItem.artistName)
                ?? "Untitled Collection"
            let subtitle = artistSubtitle(from: group)
            let artworkURL = group.compactMap(\.artworkURL).first
            let hasUnavailableTracks = group.contains { $0.availability == .unavailable }

            return MusicCollectionSummary(
                key: key,
                title: title,
                subtitle: subtitle,
                artworkURL: artworkURL,
                trackCount: group.count,
                hasUnavailableTracks: hasUnavailableTracks
            )
        }
        .sorted {
            if $0.trackCount == $1.trackCount {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.trackCount > $1.trackCount
        }
    }

    private static func artistSubtitle(from items: [MusicLibraryItem]) -> String? {
        let artists = Array(Set(items.compactMap { cleanedText($0.artistName) })).sorted()

        switch artists.count {
        case 0:
            return nil
        case 1:
            return artists[0]
        default:
            return "\(artists.count) artists"
        }
    }

    private static func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func cleanedKey(_ value: String?) -> String? {
        cleanedText(value)
    }
}

struct MusicCollectionDetailPresentation: Equatable {
    let title: String
    let navigationTitle: String
    let subtitle: String?
    let trackCountLabel: String
    let chainTitle: String
    let hasUnavailableTracks: Bool
    let metadataStatus: String?

    init(summary: MusicCollectionSummary, items: [MusicLibraryItem], chain: Chain) {
        self.title = summary.title
        self.navigationTitle = summary.title
        self.subtitle = summary.subtitle
        self.trackCountLabel = summary.trackCountLabel
        self.chainTitle = chain.routingDisplayName
        self.hasUnavailableTracks = summary.hasUnavailableTracks

        if items.isEmpty {
            self.metadataStatus = "This collection currently has no scoped music items."
        } else if summary.subtitle == nil || summary.artworkURL == nil {
            self.metadataStatus = "Some collection metadata is still being inferred from local music index fields."
        } else {
            self.metadataStatus = nil
        }
    }
}

private struct MusicCollectionTrackRow: View {
    let item: MusicLibraryItem

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: item.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        SystemImage("music.note")
                            .foregroundStyle(.gray)
                    }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                if let artist = item.artistName, !artist.isEmpty {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MusicCollectionMetaChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
