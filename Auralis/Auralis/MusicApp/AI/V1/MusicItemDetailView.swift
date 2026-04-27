import SwiftData
import SwiftUI

struct MusicItemDetailView: View {
    let itemID: String
    let currentAccountAddress: String?
    let currentChain: Chain
    let onOpenCollection: (MusicCollectionSummary) -> Void

    @Query private var nfts: [NFT]
    @Query private var libraryItems: [MusicLibraryItem]

    init(
        itemID: String,
        currentAccountAddress: String?,
        currentChain: Chain,
        onOpenCollection: @escaping (MusicCollectionSummary) -> Void
    ) {
        self.itemID = itemID
        self.currentAccountAddress = currentAccountAddress
        self.currentChain = currentChain
        self.onOpenCollection = onOpenCollection

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccountAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _nfts = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
        _libraryItems = Query(
            filter: #Predicate<MusicLibraryItem> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
    }

    private var nft: NFT? {
        nfts.first { $0.id == itemID }
    }

    private var libraryItem: MusicLibraryItem? {
        libraryItems.first { $0.sourceNFTID == itemID }
    }

    private var presentation: MusicItemDetailPresentation? {
        MusicItemDetailPresentation(nft: nft, libraryItem: libraryItem)
    }

    var body: some View {
        Group {
            if let presentation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        artworkCard(for: presentation)

                        VStack(alignment: .leading, spacing: 10) {
                            Title2FontText(presentation.title)
                                .accessibilityIdentifier("music.detail.title")

                            if let artist = presentation.artist {
                                Text(artist)
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(Color.textSecondary)
                            }

                            if let collection = presentation.collection {
                                Button {
                                    if let summary = presentation.collectionSummary {
                                        onOpenCollection(summary)
                                    }
                                } label: {
                                    MusicDetailChip(
                                        title: collection,
                                        systemImage: "square.stack.3d.up"
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if let metadataStatus = presentation.metadataStatus {
                                Text(metadataStatus)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }

                        if let playback = presentation.playbackSummary {
                            AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HeadlineFontText(playback.title)
                                    SecondaryText(playback.message)
                                }
                            }
                            .accessibilityIdentifier("music.detail.playback")
                        }

                        AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                HeadlineFontText("Track Info")

                                MusicDetailRow(title: "Track", value: presentation.title)
                                MusicDetailRow(title: "Artist", value: presentation.artist)
                                MusicDetailRow(title: "Collection", value: presentation.collection)
                                MusicDetailRow(title: "Network", value: presentation.chainTitle)
                                MusicDetailRow(title: "Format", value: presentation.contentType)
                            }
                        }

                        if let description = presentation.description {
                            AuraSurfaceCard(style: .soft, cornerRadius: 24, padding: 16) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HeadlineFontText("About")
                                    SecondaryText(description)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.background)
                .navigationTitle(presentation.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("music.detail.screen")
            } else {
                ContentUnavailableView(
                    "Track Unavailable",
                    systemImage: "music.note.slash",
                    description: Text("The requested music item could not be resolved for the current account and chain scope.")
                )
                .navigationTitle("Track Detail")
                .accessibilityIdentifier("music.detail.unavailable")
            }
        }
    }

    @ViewBuilder
    private func artworkCard(for presentation: MusicItemDetailPresentation) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: presentation.artworkURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.secondary.opacity(0.18))
                    .overlay {
                        SystemImage("music.note")
                            .font(.system(size: 42))
                            .foregroundStyle(Color.textSecondary)
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    MusicDetailChip(title: presentation.chainTitle, systemImage: "link")

                    if let format = presentation.contentType {
                        MusicDetailChip(title: format, systemImage: "waveform")
                    }
                }

                if let collection = presentation.collection {
                    Text(collection)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
            .padding(18)
        }
    }
}

struct MusicItemDetailPresentation: Equatable {
    struct PlaybackSummary: Equatable {
        let title: String
        let message: String
    }

    let title: String
    let navigationTitle: String
    let artist: String?
    let collection: String?
    let description: String?
    let artworkURL: URL?
    let chainTitle: String
    let contentType: String?
    let metadataStatus: String?
    let playbackSummary: PlaybackSummary?
    let collectionSummary: MusicCollectionSummary?

    init?(nft: NFT?, libraryItem: MusicLibraryItem?) {
        guard nft != nil || libraryItem != nil else {
            return nil
        }

        let resolvedTitle = Self.cleanedText(nft?.name)
            ?? Self.cleanedText(libraryItem?.title)
            ?? "Unknown Track"
        let resolvedArtist = Self.cleanedText(libraryItem?.artistName)
            ?? Self.cleanedText(nft?.artistName)
        let resolvedCollection = Self.cleanedText(libraryItem?.collectionName)
            ?? Self.cleanedText(nft?.collection?.name)
            ?? Self.cleanedText(nft?.collectionName)
        let resolvedDescription = Self.cleanedText(nft?.nftDescription)
        let resolvedArtworkURL = libraryItem?.artworkURL
            ?? Self.url(from: nft?.image?.originalUrl)
            ?? Self.url(from: nft?.image?.thumbnailUrl)
        let resolvedChainTitle = nft?.network?.routingDisplayName
            ?? Chain(rawValue: libraryItem?.networkRawValue ?? "")?.routingDisplayName
            ?? "Current scope"
        let resolvedContentType = Self.cleanedText(libraryItem?.contentType)
            ?? Self.cleanedText(nft?.contentType)
        let playbackURLString = Self.cleanedText(libraryItem?.playbackURLString)
            ?? Self.cleanedText(nft?.musicURL?.absoluteString)

        self.title = resolvedTitle
        self.navigationTitle = resolvedTitle
        self.artist = resolvedArtist
        self.collection = resolvedCollection
        self.description = resolvedDescription
        self.artworkURL = resolvedArtworkURL
        self.chainTitle = resolvedChainTitle
        self.contentType = resolvedContentType
        if let collectionKey = Self.cleanedText(libraryItem?.normalizedCollectionKey),
           let collectionTitle = resolvedCollection {
            self.collectionSummary = MusicCollectionSummary(
                key: collectionKey,
                title: collectionTitle,
                subtitle: resolvedArtist,
                artworkURL: resolvedArtworkURL,
                trackCount: 1,
                hasUnavailableTracks: libraryItem?.availability == .unavailable
            )
        } else {
            self.collectionSummary = nil
        }

        if nft == nil, libraryItem != nil {
            self.metadataStatus = "Showing indexed music metadata because the source NFT is not currently available in this scope."
        } else if resolvedArtist == nil || resolvedCollection == nil || resolvedDescription == nil {
            self.metadataStatus = "Some music metadata is still sparse for this item."
        } else {
            self.metadataStatus = nil
        }

        if let libraryItem {
            switch libraryItem.availability {
            case .ready where playbackURLString != nil:
                self.playbackSummary = PlaybackSummary(
                    title: "Playback Available",
                    message: "This track has a playable audio source in the current local music index."
                )
            case .ready:
                self.playbackSummary = PlaybackSummary(
                    title: "Metadata Ready",
                    message: "This track is indexed locally, but the playable source URL is currently missing."
                )
            case .unavailable:
                self.playbackSummary = PlaybackSummary(
                    title: "Playback Unavailable",
                    message: Self.cleanedText(libraryItem.availabilityReason)
                        ?? "This item still has metadata, but the current music source is not playable."
                )
            }
        } else if playbackURLString != nil {
            self.playbackSummary = PlaybackSummary(
                title: "Playback Available",
                message: "A playable music source is present on the source NFT metadata."
            )
        } else {
            self.playbackSummary = PlaybackSummary(
                title: "Metadata Only",
                message: "This music item currently resolves as metadata without a confirmed playable source."
            )
        }
    }

    private static func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func url(from value: String?) -> URL? {
        guard let cleaned = cleanedText(value) else {
            return nil
        }
        return URL.sanitizedRemoteMediaURL(from: cleaned)
    }
}

private struct MusicDetailRow: View {
    let title: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

private struct MusicDetailChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.16), in: Capsule())
    }
}
