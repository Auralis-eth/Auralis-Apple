import AuralisPrimaryModels
import SwiftData
import SwiftUI

struct AuraPlayMusicCollectionDetailView: View {
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

    private var presentation: AuraPlayMusicCollectionDetailPresentation {
        AuraPlayMusicCollectionDetailPresentation(
            title: collectionTitle,
            subtitle: subtitle,
            trackCount: items.count,
            chainTitle: currentChain.routingDisplayName,
            hasUnavailableTracks: items.contains { $0.availability == .unavailable },
            metadataStatus: metadataStatus
        )
    }

    private var subtitle: String? {
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

    private var metadataStatus: String? {
        if items.isEmpty {
            return "This collection currently has no scoped music items."
        }
        if subtitle == nil || items.compactMap(\.artworkURL).first == nil {
            return "Some collection metadata is still being inferred from local music index fields."
        }
        return nil
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
                            collectionMetaChip(
                                title: presentation.trackCountLabel,
                                systemImage: "music.note.list"
                            )
                            collectionMetaChip(
                                title: presentation.chainTitle,
                                systemImage: "link"
                            )
                            if presentation.hasUnavailableTracks {
                                collectionMetaChip(
                                    title: "Partial",
                                    systemImage: "exclamationmark.triangle"
                                )
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
                            collectionTrackRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("auraplay.collection.track.\(item.id)")
                    }
                }
            }
            .padding()
        }
        .background(Color.background)
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("auraplay.collection.detail")
    }

    private func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func collectionTrackRow(item: MusicLibraryItem) -> some View {
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
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func collectionMetaChip(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

struct AuraPlayMusicCollectionSummary: Equatable {
    let key: String
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let trackCount: Int
    let hasUnavailableTracks: Bool

    static func summaries(from items: [MusicLibraryItem]) -> [AuraPlayMusicCollectionSummary] {
        let groupedItems = Dictionary(grouping: items) { item in
            let key = cleanedText(item.normalizedCollectionKey)
            return key ?? "__ungrouped__"
        }

        return groupedItems
            .map { key, items in
                let sortedItems = items.sorted {
                    ($0.normalizedArtistKey, $0.normalizedTitleKey, $0.id) <
                        ($1.normalizedArtistKey, $1.normalizedTitleKey, $1.id)
                }
                let title = cleanedText(sortedItems.compactMap(\.collectionName).first)
                    ?? cleanedText(sortedItems.compactMap(\.artistName).first)
                    ?? "Unknown Collection"
                let artists = Array(Set(sortedItems.compactMap { cleanedText($0.artistName) })).sorted()
                let subtitle: String? = switch artists.count {
                case 0:
                    nil
                case 1:
                    artists[0]
                default:
                    "\(artists.count) artists"
                }

                return AuraPlayMusicCollectionSummary(
                    key: key,
                    title: title,
                    subtitle: subtitle,
                    artworkURL: sortedItems.compactMap(\.artworkURL).first,
                    trackCount: sortedItems.count,
                    hasUnavailableTracks: sortedItems.contains { $0.availability == .unavailable }
                )
            }
            .sorted {
                ($0.title.localizedLowercase, $0.key) < ($1.title.localizedLowercase, $1.key)
            }
    }

    private static func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

struct AuraPlayMusicCollectionDetailPresentation: Equatable {
    let title: String
    let subtitle: String?
    let trackCount: Int
    let chainTitle: String
    let hasUnavailableTracks: Bool
    let metadataStatus: String?

    var navigationTitle: String { title }
    var trackCountLabel: String {
        "\(trackCount) track" + (trackCount == 1 ? "" : "s")
    }
}
