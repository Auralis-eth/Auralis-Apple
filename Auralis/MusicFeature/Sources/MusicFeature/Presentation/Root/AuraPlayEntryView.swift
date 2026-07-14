import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import Observation
import SwiftData
import SwiftUI

/// Root presentation model for the active AuraPlay Phase 2 persistence seam.
@Observable
@MainActor
public final class AuraPlayRootModel {
    @ObservationIgnored
    let libraryRepository: any AuraPlayLibraryRepository

    @ObservationIgnored
    let librarySyncService: any AuraPlayLibrarySyncing

    @ObservationIgnored
    public let playbackController: any AuraPlayPlaybackControlling

    @ObservationIgnored
    let queueCoordinator: any AuraPlayQueueCoordinating

    @ObservationIgnored
    let artworkLoader: any AuraPlayArtworkLoading

    @ObservationIgnored
    let logger: any AuraPlayLogging

    @ObservationIgnored
    let configuration: AuraPlayModuleConfiguration

    @ObservationIgnored
    let urlResolver: URLResolver

    public private(set) var currentAccount: EOAccount?
    public private(set) var currentChain: Chain

    public var libraryItemCount: Int?
    public var upcomingQueueCount: Int
    public var playbackHistoryCount: Int
    public var currentArtworkURL: URL?
    public var lastError: AuraPlayError?
    public var configurationStatus: String
    public var statusMessage: String

    public init(
        libraryRepository: any AuraPlayLibraryRepository,
        librarySyncService: any AuraPlayLibrarySyncing,
        playbackController: any AuraPlayPlaybackControlling,
        queueCoordinator: any AuraPlayQueueCoordinating,
        artworkLoader: any AuraPlayArtworkLoading,
        logger: any AuraPlayLogging,
        configuration: AuraPlayModuleConfiguration,
        urlResolver: URLResolver,
        currentAccount: EOAccount?,
        currentChain: Chain
    ) {
        self.libraryRepository = libraryRepository
        self.librarySyncService = librarySyncService
        self.playbackController = playbackController
        self.queueCoordinator = queueCoordinator
        self.artworkLoader = artworkLoader
        self.logger = logger
        self.configuration = configuration
        self.urlResolver = urlResolver
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.upcomingQueueCount = 0
        self.playbackHistoryCount = 0
        self.currentArtworkURL = nil
        self.configurationStatus = Self.makeConfigurationStatus(configuration)
        self.statusMessage = "AuraPlay is ready to play wallet-scoped tracks for the current account and chain."
    }

    public var scope: AuraPlayLibraryScope {
        AuraPlayLibraryScope(
            accountAddress: currentAccount?.address,
            chain: currentChain
        )
    }

    public func updateContext(
        currentAccount: EOAccount?,
        currentChain: Chain
    ) {
        let accountChanged = self.currentAccount?.address != currentAccount?.address
        let chainChanged = self.currentChain != currentChain

        guard accountChanged || chainChanged else {
            return
        }

        self.currentAccount = currentAccount
        self.currentChain = currentChain
        configurationStatus = Self.makeConfigurationStatus(configuration)
    }

    public func refreshLibrarySummary() async {
        logger.log(
            AuraPlayLogEvent(
                category: .library,
                level: .info,
                message: "Refreshing AuraPlay library summary for \(scope.accountAddress == nil ? "no active account" : "active account") on \(scope.chain.rawValue)"
            )
        )

        do {
            try await librarySyncService.syncLibrary(
                in: scope,
                accountName: currentAccount?.name
            )
            libraryItemCount = try libraryRepository.itemCount(in: scope)
            lastError = nil
        } catch {
            libraryItemCount = nil
            lastError = AuraPlayError.library(error)
            statusMessage = "AuraPlay could not refresh the library summary yet."
            logger.log(
                AuraPlayLogEvent(
                    category: .library,
                    level: .error,
                    message: lastError?.localizedDescription ?? "AuraPlay library refresh failed."
                )
            )
        }

        let queueSnapshot = queueCoordinator.snapshot()
        upcomingQueueCount = queueSnapshot.upcomingCount
        playbackHistoryCount = queueSnapshot.historyCount

        do {
            currentArtworkURL = try resolvedArtworkURL(for: playbackController.currentTrack)
        } catch let error as AuraPlayError {
            currentArtworkURL = nil
            lastError = error
            logger.log(
                AuraPlayLogEvent(
                    category: .artwork,
                    level: .error,
                    message: error.localizedDescription
                )
            )
        } catch {
            currentArtworkURL = nil
            let mappedError = AuraPlayError.artwork(error)
            lastError = mappedError
            logger.log(
                AuraPlayLogEvent(
                    category: .artwork,
                    level: .error,
                    message: mappedError.localizedDescription
                )
            )
        }

        if let lastError {
            statusMessage = lastError.localizedDescription
        } else if configuration.missingRequirements.isEmpty {
            statusMessage = "AuraPlay is ready. Library, playback, queue, artwork, and account-scoped storage are available."
        } else {
            statusMessage = "AuraPlay is available, but part of the local media setup needs attention."
        }
    }

    private static func makeConfigurationStatus(_ configuration: AuraPlayModuleConfiguration) -> String {
        if configuration.missingRequirements.isEmpty {
            return "Bundle contract ready"
        }
        return configuration.missingRequirements.joined(separator: " ")
    }

    private func resolvedArtworkURL(for track: AuraPlayTrack?) throws -> URL? {
        if let imageURLString = track?.imageURLString,
           let resolvedURL = urlResolver.resolve(imageURLString) {
            return resolvedURL
        }
        return try artworkLoader.artworkURL(for: track)
    }
}

struct AuraPlayEntryView: View {
    @Bindable var model: AuraPlayRootModel
    let currentAccount: EOAccount?
    let currentChain: Chain
    let onOpenItem: (String) -> Void
    let onOpenCollection: (String, String) -> Void
    let onPlayItem: (String) async -> Void
    let onAddItemToQueue: (String) async -> Void

    @Query private var allLibraryItems: [MusicLibraryItem]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var libraryFilter: AuraPlayLibraryFilter = .all
    @State private var librarySort: AuraPlayLibrarySort = .title

    init(
        model: AuraPlayRootModel,
        currentAccount: EOAccount?,
        currentChain: Chain,
        onOpenItem: @escaping (String) -> Void,
        onOpenCollection: @escaping (String, String) -> Void,
        onPlayItem: @escaping (String) async -> Void,
        onAddItemToQueue: @escaping (String) async -> Void
    ) {
        self.model = model
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.onOpenItem = onOpenItem
        self.onOpenCollection = onOpenCollection
        self.onPlayItem = onPlayItem
        self.onAddItemToQueue = onAddItemToQueue

        let sortDescriptors: [SortDescriptor<MusicLibraryItem>] = [
            SortDescriptor(\MusicLibraryItem.normalizedCollectionKey),
            SortDescriptor(\MusicLibraryItem.normalizedArtistKey),
            SortDescriptor(\MusicLibraryItem.normalizedTitleKey),
            SortDescriptor(\MusicLibraryItem.id)
        ]
        _allLibraryItems = Query(sort: sortDescriptors)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                librarySummaryCard
                libraryControls
                collectionsSection
                tracksSection
                mediaIntegrationSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("Music")
        .accessibilityIdentifier(A11yID.AuraPlay.root)
        .task(
            id: "\(model.currentAccount?.address ?? "none")|\(model.currentChain.rawValue)"
        ) {
            await model.refreshLibrarySummary()
        }
    }

    private var libraryItems: [MusicLibraryItem] {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue
        return allLibraryItems.filter {
            $0.accountAddressRawValue == normalizedAccountAddress &&
            $0.networkRawValue == chainRawValue
        }
    }

    private var visibleLibraryItems: [MusicLibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredItems = libraryItems.filter { item in
            libraryFilter.includes(item) && (query.isEmpty || item.matchesLibrarySearch(query))
        }
        return librarySort.sort(filteredItems)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            AuraPill("AuraPlay", systemImage: "waveform.circle", emphasis: .accent)
                AuraSectionHeader(
                    title: "AuraPlay Library",
                    subtitle: "Wallet-scoped tracks, queue controls, recent playback, video preview, and media availability."
                )
        }
    }

    private var librarySummaryCard: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 28, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Library Ready", systemImage: "music.note.list")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Text(model.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                infoRow(title: "Account", value: currentAccount?.name ?? currentAccount?.address ?? "No active account")
                infoRow(title: "Chain", value: currentChain.routingDisplayName)
                infoRow(title: "Tracks", value: String(libraryItems.count))
                infoRow(title: "Playable", value: String(libraryItems.filter(\.isPlaybackReady).count))
                infoRow(title: "Visible", value: String(visibleLibraryItems.count))
                infoRow(title: "Playback", value: String(describing: model.playbackController.playbackState).capitalized)
                infoRow(title: "Queue", value: "\(model.upcomingQueueCount) upcoming, \(model.playbackHistoryCount) recent")
                infoRow(title: "Bundle", value: model.configurationStatus)
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.librarySummary)
    }

    private var libraryControls: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityHidden(true)

                    TextField("Search tracks, artists, collections", text: $searchText)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .disableAutocorrection(true)
                        .accessibilityIdentifier(A11yID.AuraPlay.librarySearch)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                Picker("Filter", selection: $libraryFilter) {
                    ForEach(AuraPlayLibraryFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.systemImage)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(A11yID.AuraPlay.libraryFilter)

                HStack {
                    Label("Showing \(visibleLibraryItems.count) of \(libraryItems.count)", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    Spacer()

                    Picker("Sort", selection: $librarySort) {
                        ForEach(AuraPlayLibrarySort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier(A11yID.AuraPlay.librarySort)
                }
            }
        }
    }

    @ViewBuilder
    private var collectionsSection: some View {
        let summaries = AuraPlayMusicCollectionSummary.summaries(from: visibleLibraryItems)
        AuraPlayLibrarySection(title: "Collections", systemImage: "square.stack.3d.up") {
            if summaries.isEmpty {
                AuraPlayEmptyLibraryCard(
                    title: "No collections yet",
                    message: "Music NFTs will appear here after the current wallet scope has playable metadata."
                )
            } else {
                ForEach(summaries.prefix(8), id: \.key) { summary in
                    Button {
                        onOpenCollection(summary.key, summary.title)
                    } label: {
                        AuraPlayCollectionRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(A11yID.AuraPlay.collectionRow(id: summary.key))
                }
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.collections)
    }

    @ViewBuilder
    private var tracksSection: some View {
        AuraPlayLibrarySection(title: "Tracks", systemImage: "music.note") {
            if visibleLibraryItems.isEmpty {
                AuraPlayEmptyLibraryCard(
                    title: libraryItems.isEmpty ? "No tracks indexed" : "No matching tracks",
                    message: libraryItems.isEmpty ? "Sync the wallet library to populate AuraPlay tracks for this chain." : "Adjust search, media type, or availability filters to show more library items."
                )
            } else {
                ForEach(visibleLibraryItems.prefix(12)) { item in
                    AuraPlayTrackRow(
                        item: item,
                        open: { onOpenItem(item.sourceNFTID) },
                        play: { Task { await onPlayItem(item.sourceNFTID) } },
                        addToQueue: { Task { await onAddItemToQueue(item.sourceNFTID) } }
                    )
                    .accessibilityIdentifier(A11yID.AuraPlay.trackRow(id: item.id))
                }
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.tracks)
    }

    private var mediaIntegrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuraPlayLibrarySection(title: "Media Controls", systemImage: "slider.horizontal.3") {
                AuraPlayIntegrationStatusRow(
                    title: "Video player",
                    message: "Wallet-scoped video items open in a real AVPlayer-backed surface with PiP, route, track, chapter, speed, and resume controls when metadata provides them.",
                    systemImage: "play.rectangle",
                    status: "Backed"
                )
                AuraPlayIntegrationStatusRow(
                    title: "Offline cache",
                    message: "Audio playback exposes save, pin, unpin, and cache progress controls from the media cache manager.",
                    systemImage: "arrow.down.circle",
                    status: "Backed"
                )
                AuraPlayIntegrationStatusRow(
                    title: "Shared session",
                    message: "Shared listening and watching controls stay hidden until participant and shared-queue state are real.",
                    systemImage: "shareplay",
                    status: "Planned"
                )
            }
        }
    }

    private func infoRow(title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                infoRowTitle(title)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 96 : 124, alignment: .leading)

                infoRowValue(value)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                infoRowTitle(title)
                infoRowValue(value)
            }
        }
    }

    private func infoRowTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
    }

    private func infoRowValue(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AuraPlayLibrarySection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            content
        }
    }
}

private struct AuraPlayEmptyLibraryCard: View {
    let title: String
    let message: String

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

private struct AuraPlayCollectionRow: View {
    let summary: AuraPlayMusicCollectionSummary

    var body: some View {
        HStack(spacing: 14) {
            AsyncImage(url: summary.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.16))
                    .overlay {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityHidden(true)
                    }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 12))
            .mediaAccessibility(.decorative)

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(summary.subtitle ?? summary.trackCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Label(summary.trackCountLabel, systemImage: summary.hasUnavailableTracks ? "exclamationmark.triangle" : "music.note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .labelStyle(.titleAndIcon)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct AuraPlayTrackRow: View {
    let item: MusicLibraryItem
    let open: () -> Void
    let play: () -> Void
    let addToQueue: () -> Void

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 18, padding: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: item.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.16))
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(Color.textSecondary)
                                .accessibilityHidden(true)
                        }
                }
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: 10))
                .mediaAccessibility(.decorative)

                Button(action: open) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        Text(item.artistName ?? item.collectionName ?? item.chainTitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button(action: play) {
                        Image(systemName: "play.fill")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!item.isPlaybackReady)
                    .accessibilityLabel("Play \(item.title)") // [VERIFY] item title is the playback label.
                    .accessibilityHint("Starts playback for this track")

                    Button(action: addToQueue) {
                        Image(systemName: "text.badge.plus")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!item.isPlaybackReady)
                    .accessibilityLabel("Add \(item.title) to queue") // [VERIFY] item title is the queue label.
                    .accessibilityHint("Adds this track to the upcoming queue")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private enum AuraPlayLibraryFilter: String, CaseIterable, Identifiable {
    case all
    case playable
    case audio
    case video
    case unavailable

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .playable:
            return "Playable"
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .unavailable:
            return "Missing"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .playable:
            return "play.circle"
        case .audio:
            return "music.note"
        case .video:
            return "play.rectangle"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }

    func includes(_ item: MusicLibraryItem) -> Bool {
        switch self {
        case .all:
            return true
        case .playable:
            return item.isPlaybackReady
        case .audio:
            return item.isAudioCapable
        case .video:
            return item.isVideoCapable
        case .unavailable:
            return !item.isPlaybackReady
        }
    }
}

private enum AuraPlayLibrarySort: String, CaseIterable, Identifiable {
    case title
    case artist
    case collection
    case availability

    var id: Self { self }

    var title: String {
        switch self {
        case .title:
            return "Title"
        case .artist:
            return "Artist"
        case .collection:
            return "Collection"
        case .availability:
            return "Availability"
        }
    }

    func sort(_ items: [MusicLibraryItem]) -> [MusicLibraryItem] {
        items.sorted { lhs, rhs in
            switch self {
            case .title:
                return compare(lhs.normalizedTitleKey, rhs.normalizedTitleKey, lhs.id, rhs.id)
            case .artist:
                return compare(lhs.normalizedArtistKey, rhs.normalizedArtistKey, lhs.normalizedTitleKey, rhs.normalizedTitleKey)
            case .collection:
                return compare(lhs.normalizedCollectionKey, rhs.normalizedCollectionKey, lhs.normalizedTitleKey, rhs.normalizedTitleKey)
            case .availability:
                return compare(lhs.availabilitySortKey, rhs.availabilitySortKey, lhs.normalizedTitleKey, rhs.normalizedTitleKey)
            }
        }
    }

    private func compare(_ lhsPrimary: String, _ rhsPrimary: String, _ lhsFallback: String, _ rhsFallback: String) -> Bool {
        if lhsPrimary == rhsPrimary {
            return lhsFallback.localizedStandardCompare(rhsFallback) == .orderedAscending
        }
        return lhsPrimary.localizedStandardCompare(rhsPrimary) == .orderedAscending
    }
}

private extension MusicLibraryItem {
    var isPlaybackReady: Bool {
        availability == .ready && playbackURLString?.isEmpty == false
    }

    var isAudioCapable: Bool {
        guard let contentType = contentType?.lowercased() else {
            return !isVideoCapable
        }
        return contentType.contains("audio") || contentType.contains("mpeg") || contentType.contains("mp3") || contentType.contains("wav")
    }

    var isVideoCapable: Bool {
        guard let contentType = contentType?.lowercased() else {
            return false
        }
        return contentType.contains("video") || contentType.contains("mp4") || contentType.contains("mpegurl") || contentType.contains("hls")
    }

    var availabilitySortKey: String {
        isPlaybackReady ? "0-ready" : "1-unavailable"
    }

    func matchesLibrarySearch(_ query: String) -> Bool {
        [title, artistName, collectionName, contentType, chainTitle]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
    }

    var chainTitle: String {
        Chain(rawValue: networkRawValue)?.routingDisplayName ?? "Current scope"
    }
}

private struct AuraPlayIntegrationStatusRow: View {
    let title: String
    let message: String
    let systemImage: String
    let status: String

    var body: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 18, padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .accessibilityElement(children: .combine)
        }
    }
}
