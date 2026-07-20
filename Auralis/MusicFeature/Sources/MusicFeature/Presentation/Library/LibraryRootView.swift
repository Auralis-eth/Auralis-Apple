import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import SwiftData
import SwiftUI

public struct LibraryRootView: View {
    @Bindable var model: AuraPlayRootModel
    let currentAccount: EOAccount?
    let currentChain: Chain
    let onOpenItem: (String) -> Void
    let onOpenCollection: (String, String) -> Void
    let onPlayItem: (String) async -> Void
    let onAddItemToQueue: (String) async -> Void
    let openWalletPicker: () -> Void

    @Query private var playlists: [AuraPlayPlaylist]
    @AppStorage("auraplay.library.segment") private var selectedSegmentRawValue = LibrarySegment.all.rawValue
    @AppStorage("auraplay.library.layout.all") private var allLayoutRawValue = LibraryLayoutMode.grid.rawValue
    @AppStorage("auraplay.library.layout.audio") private var audioLayoutRawValue = LibraryLayoutMode.grid.rawValue
    @AppStorage("auraplay.library.layout.video") private var videoLayoutRawValue = LibraryLayoutMode.grid.rawValue
    @State private var sort = MediaItemSort.dateAdded
    @State private var mediaTypeFilter = MediaItemMediaTypeFilter.all
    @State private var unplayedOnly = false
    @State private var path: [LibraryRoute] = []
    @State private var playlistSheet: PlaylistSheet?
    @State private var pendingPlaylistDeletion: AuraPlayPlaylist?
    @State private var playlistMutationError: String?
    @State private var showsSearchDiagnostics = false
    @Namespace private var playerTransitionNamespace

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
    ]
    private let chipColumns = [
        GridItem(.adaptive(minimum: 120), spacing: 8)
    ]

    public init(
        model: AuraPlayRootModel,
        currentAccount: EOAccount?,
        currentChain: Chain,
        onOpenItem: @escaping (String) -> Void,
        onOpenCollection: @escaping (String, String) -> Void,
        onPlayItem: @escaping (String) async -> Void,
        onAddItemToQueue: @escaping (String) async -> Void,
        openWalletPicker: @escaping () -> Void = {}
    ) {
        self.model = model
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.onOpenItem = onOpenItem
        self.onOpenCollection = onOpenCollection
        self.onPlayItem = onPlayItem
        self.onAddItemToQueue = onAddItemToQueue
        self.openWalletPicker = openWalletPicker

        _playlists = Query(
            sort: [
                SortDescriptor(\AuraPlayPlaylist.updatedAt, order: .reverse),
                SortDescriptor(\AuraPlayPlaylist.name)
            ]
        )
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        syncStatusBanner
                        segmentPicker
                        indexingPill
                        browseControls
                        segmentContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .padding(.bottom, model.playbackPresenter == nil ? 24 : 120)
                }
                .refreshable {
                    await model.refreshLibraryFromUserAction()
                }

                if let playbackPresenter = model.playbackPresenter {
                    AuraPlayMiniPlayerView(
                        player: AnyAuraPlayPlaybackPresenter(playbackPresenter),
                        orchestrator: model.playbackOrchestrator,
                        transitionNamespace: playerTransitionNamespace
                    )
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial)
                    .accessibilityIdentifier(A11yID.AuraPlay.miniPlayer)
                }
            }
            .navigationTitle("Music")
            .searchable(
                text: searchTextBinding,
                placement: .automatic,
                prompt: "Search tracks, artists, moods"
            )
            .searchSuggestions {
                auraPlaySearchSuggestions
            }
            .onSubmit(of: .search) {
                selectedSegment = .search
                model.submitSearch()
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                destination(for: route)
            }
            .toolbar {
                ToolbarItem(placement: .auraPlayBarLeading) {
                    Button {
                        playlistSheet = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create playlist")
                }
                ToolbarItem(placement: .auraPlayBarTrailing) {
                    Button {
                        openWalletPicker()
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Switch wallet")
                }
            }
            .sheet(item: $playlistSheet) { sheet in
                playlistSheetView(sheet)
            }
            .alert("Delete Playlist?", isPresented: deletePlaylistBinding) {
                Button("Delete", role: .destructive) {
                    deletePendingPlaylist()
                }
                Button("Cancel", role: .cancel) {
                    pendingPlaylistDeletion = nil
                }
            } message: {
                Text("This removes the playlist but keeps its media in your library.")
            }
            .alert("Playlist Update Failed", isPresented: playlistErrorBinding) {
                Button("OK", role: .cancel) {
                    playlistMutationError = nil
                }
            } message: {
                Text(playlistMutationError ?? "Try again.")
            }
            .background(Color.background.ignoresSafeArea())
            .accessibilityIdentifier(A11yID.AuraPlay.root)
        }
        .task(id: "\(model.currentAccount?.address ?? "none")|\(model.currentChain.rawValue)") {
            await model.refreshLibrarySummary()
        }
        .task(id: browseReloadKey) {
            await model.reloadBrowseWindow(
                sort: sort,
                mediaType: effectiveMediaFilter,
                unplayedOnly: unplayedOnly
            )
            await model.reloadGroupedIndexIfNeeded()
        }
    }

    private var browseReloadKey: String {
        [
            model.currentAccount?.address ?? "none",
            model.currentChain.rawValue,
            sort.rawValue,
            effectiveMediaFilter.rawValue,
            unplayedOnly.description
        ].joined(separator: "|")
    }

    private var selectedSegment: LibrarySegment {
        get { LibrarySegment(rawValue: selectedSegmentRawValue) ?? .all }
        nonmutating set { selectedSegmentRawValue = newValue.rawValue }
    }

    private var selectedLayout: LibraryLayoutMode {
        get {
            switch selectedSegment {
            case .audio:
                LibraryLayoutMode(rawValue: audioLayoutRawValue) ?? .grid
            case .video:
                LibraryLayoutMode(rawValue: videoLayoutRawValue) ?? .grid
            default:
                LibraryLayoutMode(rawValue: allLayoutRawValue) ?? .grid
            }
        }
        nonmutating set {
            switch selectedSegment {
            case .audio:
                audioLayoutRawValue = newValue.rawValue
            case .video:
                videoLayoutRawValue = newValue.rawValue
            default:
                allLayoutRawValue = newValue.rawValue
            }
        }
    }

    private var effectiveMediaFilter: MediaItemMediaTypeFilter {
        switch selectedSegment {
        case .audio:
            .audio
        case .video:
            .video
        default:
            mediaTypeFilter
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            AuraPill("AuraPlay", systemImage: "waveform.circle", emphasis: .accent)
            AuraSectionHeader(
                title: "Library",
                subtitle: currentAccount == nil
                    ? "Connect a wallet to discover playable NFT media."
                    : "\(currentChain.routingDisplayName) media for \(currentAccount?.name ?? currentAccount?.address ?? "active wallet")."
            )
        }
    }

    @ViewBuilder
    private var syncStatusBanner: some View {
        let progress = model.syncProgress
        switch progress.state {
        case .idle:
            EmptyView()
        case .syncing(let wallet, let chain):
            AuraSurfaceCard(style: .soft, cornerRadius: 16, padding: 12) {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Syncing \(chain.routingDisplayName)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(progress.tokensDiscovered) tokens, \(progress.itemsPlayable) playable media. \(wallet.shortWalletDisplay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(A11yID.AuraPlay.librarySyncBanner)
        case .complete:
            if let lastSyncedAt = progress.lastSyncedAt {
                AuraPill("Synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle", emphasis: .success)
                    .accessibilityIdentifier(A11yID.AuraPlay.librarySyncBanner)
            }
        case .error(let errors):
            AuraSurfaceCard(style: .soft, cornerRadius: 16, padding: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(errors.first?.message ?? "Sync failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .accessibilityIdentifier(A11yID.AuraPlay.librarySyncBanner)
        }
    }

    @ViewBuilder
    private var indexingPill: some View {
        if model.indexingStatus.isActive {
            AuraPill(model.indexingStatus.message, systemImage: "magnifyingglass.circle", emphasis: .accent)
                .accessibilityIdentifier(A11yID.AuraPlay.libraryIndexingPill)
        }
    }

    private var segmentPicker: some View {
        Picker("Library", selection: Binding(get: { selectedSegment }, set: { selectedSegment = $0 })) {
            ForEach(LibrarySegment.allCases) { segment in
                Text(segment.title).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Library segment")
        .accessibilityValue("\(selectedSegment.title), tab \(segmentIndex) of \(LibrarySegment.allCases.count)")
        .accessibilityIdentifier(A11yID.AuraPlay.librarySegmentPicker)
    }

    @ViewBuilder
    private var browseControls: some View {
        if selectedSegment == .all || selectedSegment == .audio || selectedSegment == .video {
            AuraSurfaceCard(style: .soft, cornerRadius: 18, padding: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        layoutToggle
                        Spacer()
                        sortMenu
                        Toggle("Unplayed", isOn: $unplayedOnly)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        layoutToggle
                        sortMenu
                        Toggle("Unplayed", isOn: $unplayedOnly)
                    }
                }
            }
        }
    }

    private var layoutToggle: some View {
        Picker("Layout", selection: Binding(get: { selectedLayout }, set: { selectedLayout = $0 })) {
            Image(systemName: "square.grid.2x2").tag(LibraryLayoutMode.grid)
            Image(systemName: "list.bullet").tag(LibraryLayoutMode.list)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 140)
        .accessibilityLabel("Library layout")
        .accessibilityIdentifier(A11yID.AuraPlay.libraryLayoutToggle)
    }

    private var sortMenu: some View {
        Picker("Sort", selection: $sort) {
            ForEach(MediaItemSort.allCases) { sort in
                Text(sort.title).tag(sort)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(A11yID.AuraPlay.librarySort)
    }

    @ViewBuilder
    private var segmentContent: some View {
        if currentAccount == nil {
            emptyState(
                id: A11yID.AuraPlay.libraryEmptyNoWallet,
                title: "No Wallet Connected",
                message: "Choose a wallet to discover playable audio and video NFTs.",
                systemImage: "wallet.pass",
                actionTitle: "Choose Wallet",
                action: openWalletPicker
            )
        } else if model.browseItems.isEmpty && model.libraryItemCount == nil {
            emptyState(
                id: A11yID.AuraPlay.libraryEmptySyncing,
                title: "Syncing Library",
                message: "AuraPlay is checking this wallet for playable media.",
                systemImage: "arrow.triangle.2.circlepath"
            )
        } else if (model.browseTotalCount ?? 0) == 0 && model.browseItems.isEmpty {
            emptyState(
                id: A11yID.AuraPlay.libraryEmptyNoPlayable,
                title: "No Playable Media",
                message: "This wallet has no playable AuraPlay audio or video on this chain yet.",
                systemImage: "music.note.slash"
            )
        } else {
            switch selectedSegment {
            case .all, .audio, .video:
                itemGridOrList
            case .search:
                searchContent
            case .collections:
                collectionList
            case .creators:
                creatorList
            case .playlists:
                playlistList
            }
        }
    }

    private var searchContent: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            searchControls
            if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptySearchContent
            } else {
                searchResultsContent
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.searchRoot)
        .task(id: "\(model.currentAccount?.address ?? "none")|\(model.currentChain.rawValue)") {
            model.refreshSearchRecents()
        }
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { model.searchText },
            set: { newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedSegment = .search
                }
                Task { await model.updateSearchText(newValue) }
            }
        )
    }

    @ViewBuilder
    private var auraPlaySearchSuggestions: some View {
        if model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ForEach(model.searchRecentQueries.prefix(5), id: \.self) { query in
                Label(query, systemImage: "clock.arrow.circlepath")
                    .searchCompletion(query)
            }
            ForEach(model.suggestedSearchQueries.prefix(5), id: \.self) { query in
                Label(query, systemImage: "sparkles")
                    .searchCompletion(query)
            }
        } else {
            ForEach(model.searchSuggestions) { suggestion in
                Label(suggestion.value, systemImage: suggestion.kind.systemImage)
                    .searchCompletion(suggestion.value)
            }
        }
    }

    private var searchMediaTypeBinding: Binding<MediaItemMediaTypeFilter> {
        Binding(
            get: { model.searchFilter.mediaType },
            set: { model.searchFilter.mediaType = $0 }
        )
    }

    private var searchUnplayedBinding: Binding<Bool> {
        Binding(
            get: { model.searchFilter.unplayedOnly },
            set: { model.searchFilter.unplayedOnly = $0 }
        )
    }

    private var searchCurrentChainBinding: Binding<Bool> {
        Binding(
            get: { model.searchFilter.selectedChains.contains(currentChain) },
            set: { isEnabled in
                if isEnabled {
                    model.searchFilter.selectedChains.insert(currentChain)
                } else {
                    model.searchFilter.selectedChains.remove(currentChain)
                }
            }
        )
    }

    private var searchControls: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 18, padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                if model.isSearchRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching AuraPlay library")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(A11yID.AuraPlay.searchField)
                } else if !model.searchText.isEmpty {
                    Button("Clear AuraPlay Search", systemImage: "xmark.circle") {
                        model.clearSearch()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(A11yID.AuraPlay.searchClear)
                }

                if !model.searchSuggestions.isEmpty {
                    LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                        ForEach(model.searchSuggestions) { suggestion in
                            Button {
                                model.submitSearch(suggestion.value)
                            } label: {
                                Label(suggestion.value, systemImage: suggestion.kind.systemImage)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(A11yID.AuraPlay.searchSuggestion(id: suggestion.id))
                        }
                    }
                }

                searchFilterControls
            }
        }
    }

    private var searchFilterControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Picker("Media type", selection: searchMediaTypeBinding) {
                    ForEach(MediaItemMediaTypeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier(A11yID.AuraPlay.searchMediaTypeFilter)

                Toggle(currentChain.routingDisplayName, isOn: searchCurrentChainBinding)
                Toggle("Unplayed", isOn: searchUnplayedBinding)
                Button("Clear Filters", systemImage: "xmark.circle") {
                    model.clearSearchFilters()
                }
                .accessibilityIdentifier(A11yID.AuraPlay.searchClearFilters)
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("Media type", selection: searchMediaTypeBinding) {
                    ForEach(MediaItemMediaTypeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier(A11yID.AuraPlay.searchMediaTypeFilter)

                Toggle(currentChain.routingDisplayName, isOn: searchCurrentChainBinding)
                Toggle("Unplayed", isOn: searchUnplayedBinding)
                Button("Clear Filters", systemImage: "xmark.circle") {
                    model.clearSearchFilters()
                }
                .accessibilityIdentifier(A11yID.AuraPlay.searchClearFilters)
            }
        }
    }

    private var emptySearchContent: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                if !model.searchRecentQueries.isEmpty {
                    Label("Recent Searches", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                        ForEach(model.searchRecentQueries, id: \.self) { query in
                            Button(query) {
                                model.submitSearch(query)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(A11yID.AuraPlay.searchRecent(query: query))
                        }
                    }
                    Button("Clear Recent Searches", systemImage: "trash") {
                        model.clearRecentSearches()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(A11yID.AuraPlay.searchClearRecents)
                }

                if !model.suggestedSearchQueries.isEmpty {
                    Label("Suggested Searches", systemImage: "sparkles")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                        ForEach(model.suggestedSearchQueries, id: \.self) { query in
                            Button(query) {
                                model.submitSearch(query)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier(A11yID.AuraPlay.searchSuggested(query: query))
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.searchEmpty)
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        let results = model.filteredSearchResults
        VStack(alignment: .leading, spacing: 12) {
            Label("Search Results", systemImage: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 10) {
                searchResultsHeader(resultCount: results.count)

                if model.isSearchRunning && model.searchResults.isEmpty {
                    AuraSurfaceCard(style: .regular, cornerRadius: 18, padding: 16) {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching AuraPlay library")
                                .font(.subheadline)
                        }
                    }
                    .accessibilityIdentifier(A11yID.AuraPlay.searchLoading)
                } else if !model.searchResults.isEmpty && results.isEmpty {
                    emptyState(
                        id: A11yID.AuraPlay.searchFilteredEmpty,
                        title: "No Results Match Filters",
                        message: "Clear filters to show the matching AuraPlay media again.",
                        systemImage: "line.3.horizontal.decrease.circle",
                        actionTitle: "Clear Filters",
                        action: model.clearSearchFilters
                    )
                } else if results.isEmpty {
                    emptyState(
                        id: A11yID.AuraPlay.searchNoResults,
                        title: "No AuraPlay Matches",
                        message: model.searchStatus,
                        systemImage: "magnifyingglass"
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(results) { result in
                            searchCell(for: result)
                        }
                    }
                    .accessibilityIdentifier(A11yID.AuraPlay.searchResults)
                }
            }
        }
    }

    private func searchResultsHeader(resultCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(resultCount) visible - \(model.searchStatus)")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .onLongPressGesture {
                    #if DEBUG
                    showsSearchDiagnostics.toggle()
                    #endif
                }
                .accessibilityAction(named: "Toggle search diagnostics") {
                    #if DEBUG
                    showsSearchDiagnostics.toggle()
                    #endif
                }

            #if DEBUG
            if showsSearchDiagnostics {
                Text("Local \(model.searchDiagnostics.localCount) - Semantic \(model.searchDiagnostics.semanticCount) - Overlap \(model.searchDiagnostics.overlapCount)")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier(A11yID.AuraPlay.searchDiagnostics)
            }
            #endif
        }
    }

    private func searchCell(for result: AuraPlaySearchResult) -> some View {
        LibraryItemCell(
            viewModel: LibraryItemCellViewModel(
                queryItem: result.item,
                isCurrent: model.playbackController.currentTrackID == result.item.sourceNFTID
            ),
            layout: .list,
            play: { Task { await playFromSearch(itemID: result.item.sourceNFTID) } },
            open: { onOpenItem(result.item.sourceNFTID) },
            addToPlaylist: { playlistSheet = .addItem(result.item.sourceNFTID) }
        )
        .overlay(alignment: .topTrailing) {
            #if DEBUG
            Text(result.source.title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())
                .padding(6)
                .accessibilityHidden(true)
            #endif
        }
        .accessibilityIdentifier(A11yID.AuraPlay.searchResult(id: result.id))
    }

    @ViewBuilder
    private var itemGridOrList: some View {
        if selectedLayout == .grid {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.browseItems) { item in
                    cell(for: item, layout: .grid)
                }
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(model.browseItems) { item in
                    cell(for: item, layout: .list)
                }
            }
        }
    }

    private func cell(for item: MediaItemQueryItem, layout: LibraryLayoutMode) -> some View {
        LibraryItemCell(
            viewModel: LibraryItemCellViewModel(
                queryItem: item,
                isCurrent: model.playbackController.currentTrackID == item.sourceNFTID
            ),
            layout: layout,
            play: { Task { await playFromBrowse(itemID: item.sourceNFTID) } },
            open: { onOpenItem(item.sourceNFTID) },
            addToPlaylist: { playlistSheet = .addItem(item.sourceNFTID) }
        )
        .onAppear {
            Task { await model.loadMoreBrowseItemsIfNeeded(visibleItemID: item.sourceNFTID) }
        }
    }

    /// Playable taps start playback through the orchestrator with a bounded
    /// 100-item window plus captured query context for lazy extension (P9-002).
    private func playFromBrowse(itemID: String) async {
        if let orchestrator = model.playbackOrchestrator,
           let pair = model.browseQueueWindow(startingAt: itemID) {
            await orchestrator.play(
                item: pair.item,
                queue: pair.window,
                startAt: pair.window.startIndex,
                origin: pair.window.origin
            )
        } else {
            await onPlayItem(itemID)
        }
    }

    private func playFromSearch(itemID: String) async {
        if let orchestrator = model.playbackOrchestrator,
           let pair = model.searchQueueWindow(startingAt: itemID) {
            await orchestrator.play(
                item: pair.item,
                queue: pair.window,
                startAt: pair.window.startIndex,
                origin: pair.window.origin
            )
        } else {
            await onPlayItem(itemID)
        }
    }

    private func playFromList(
        itemID: String,
        items: [MediaItemQueryItem],
        origin: AuraPlayQueueOriginPresentation
    ) async {
        if let orchestrator = model.playbackOrchestrator,
           let pair = model.listQueueWindow(startingAt: itemID, in: items, origin: origin) {
            await orchestrator.play(
                item: pair.item,
                queue: pair.window,
                startAt: pair.window.startIndex,
                origin: origin
            )
        } else {
            await onPlayItem(itemID)
        }
    }

    private var collectionList: some View {
        LazyVStack(spacing: 10) {
            ForEach(model.groupedIndex?.collections ?? []) { group in
                Button {
                    path.append(.collection(group.id))
                } label: {
                    groupRow(title: group.collectionName, subtitle: "\(group.itemCount) items", systemImage: "rectangle.stack")
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Open in App Detail", systemImage: "arrow.up.forward.square") {
                        onOpenCollection(group.contractAddress ?? group.collectionName, group.collectionName)
                    }
                }
                .accessibilityIdentifier(A11yID.AuraPlay.collectionRow(id: group.id))
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.collections)
    }

    private var creatorList: some View {
        LazyVStack(spacing: 10) {
            ForEach(model.groupedIndex?.creators ?? []) { group in
                Button {
                    path.append(.creator(group.id))
                } label: {
                    groupRow(title: group.displayName, subtitle: "\(group.itemCount) items", systemImage: "person.crop.square")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11yID.AuraPlay.creatorRow(id: group.id))
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.creators)
    }

    private var playlistList: some View {
        LazyVStack(spacing: 10) {
            if playlists.isEmpty {
                emptyState(
                    id: A11yID.AuraPlay.playlists,
                    title: "No Playlists",
                    message: "Create playlists from a media item menu.",
                    systemImage: "music.note.list"
                )
            } else {
                ForEach(playlists) { playlist in
                    Button {
                        path.append(.playlist(playlist.id))
                    } label: {
                        groupRow(
                            title: playlist.name,
                            subtitle: "\(playlist.items.count) items",
                            systemImage: playlist.isSmart ? "sparkles" : "music.note.list"
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            playlistSheet = .rename(playlist.id, playlist.name)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingPlaylistDeletion = playlist
                        }
                    }
                    .accessibilityIdentifier(A11yID.AuraPlay.playlistRow(id: playlist.id))
                }
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.playlists)
    }

    private func groupRow(title: String, subtitle: String, systemImage: String) -> some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 18, padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 36, height: 36)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func emptyState(
        id: String,
        title: String,
        message: String,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 24, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                AuraEmptyState(title: title, message: message, systemImage: systemImage)
                if let actionTitle, let action {
                    Button(actionTitle, systemImage: "arrow.right", action: action)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func destination(for route: LibraryRoute) -> some View {
        switch route {
        case .collection(let id):
            LibraryGroupDetailLoaderView(
                model: model,
                group: .collection(id: id),
                title: model.groupedIndex?.collections.first(where: { $0.id == id })?.collectionName ?? "Collection",
                systemImage: "rectangle.stack",
                sort: sort,
                currentTrackID: model.playbackController.currentTrackID,
                origin: .collection(contractAddress: id),
                onOpenItem: onOpenItem,
                onPlayItem: playFromList,
                onAddToPlaylist: { playlistSheet = .addItem($0) }
            )
            .accessibilityIdentifier(A11yID.AuraPlay.collectionDetail)
        case .creator(let id):
            LibraryGroupDetailLoaderView(
                model: model,
                group: .creator(id: id),
                title: model.groupedIndex?.creators.first(where: { $0.id == id })?.displayName ?? "Creator",
                systemImage: "person.crop.square",
                sort: sort,
                currentTrackID: model.playbackController.currentTrackID,
                origin: .creator(id: id),
                onOpenItem: onOpenItem,
                onPlayItem: playFromList,
                onAddToPlaylist: { playlistSheet = .addItem($0) }
            )
        case .playlist(let id):
            if let playlist = playlists.first(where: { $0.id == id }) {
                LibraryPlaylistDetailLoaderView(
                    model: model,
                    playlist: playlist,
                    currentTrackID: model.playbackController.currentTrackID,
                    rename: { playlistSheet = .rename(playlist.id, playlist.name) },
                    delete: { pendingPlaylistDeletion = playlist },
                    onOpenItem: onOpenItem,
                    onPlayItem: playFromList,
                    onRemoveItem: { mediaItemID in
                        Task {
                            await mutatePlaylist {
                                try await model.playlistManager.remove(
                                    mediaItemID: mediaItemID,
                                    fromPlaylist: playlist.id,
                                    at: .now
                                )
                            }
                        }
                    },
                    onMoveItem: { source, destination in
                        Task {
                            await mutatePlaylist {
                                try await model.playlistManager.reorderItem(
                                    playlistID: playlist.id,
                                    fromPosition: source,
                                    toPosition: destination,
                                    at: .now
                                )
                            }
                        }
                    }
                )
            } else {
                emptyState(
                    id: A11yID.AuraPlay.playlists,
                    title: "Playlist Missing",
                    message: "This playlist is no longer available.",
                    systemImage: "music.note.list"
                )
            }
        }
    }

    @ViewBuilder
    private func playlistSheetView(_ sheet: PlaylistSheet) -> some View {
        switch sheet {
        case .create:
            PlaylistNameEditorSheet(
                title: "New Playlist",
                initialName: "",
                submitTitle: "Create"
            ) { name in
                await mutatePlaylist {
                    _ = try await model.playlistManager.createID(name: name, at: .now)
                }
            }
        case .rename(let id, let currentName):
            PlaylistNameEditorSheet(
                title: "Rename Playlist",
                initialName: currentName,
                submitTitle: "Rename"
            ) { name in
                await mutatePlaylist {
                    try await model.playlistManager.rename(id: id, name: name, at: .now)
                }
            }
        case .addItem(let mediaItemID):
            AddToPlaylistSheet(
                playlists: playlists,
                mediaItemID: mediaItemID,
                createAndAdd: { name in
                    await mutatePlaylist {
                        _ = try await model.playlistManager.createAndAddID(
                            name: name,
                            mediaItemID: mediaItemID,
                            at: .now
                        )
                    }
                },
                toggle: { playlistID in
                    await mutatePlaylist(closeOnSuccess: false) {
                        try await model.playlistManager.toggle(
                            mediaItemID: mediaItemID,
                            playlistID: playlistID,
                            at: .now
                        )
                    }
                }
            )
        }
    }

    private var deletePlaylistBinding: Binding<Bool> {
        Binding(
            get: { pendingPlaylistDeletion != nil },
            set: { if !$0 { pendingPlaylistDeletion = nil } }
        )
    }

    private var playlistErrorBinding: Binding<Bool> {
        Binding(
            get: { playlistMutationError != nil },
            set: { if !$0 { playlistMutationError = nil } }
        )
    }

    private func deletePendingPlaylist() {
        guard let playlist = pendingPlaylistDeletion else { return }
        pendingPlaylistDeletion = nil
        path.removeAll { route in
            if case .playlist(let id) = route {
                return id == playlist.id
            }
            return false
        }
        Task {
            await mutatePlaylist {
                try await model.playlistManager.delete(id: playlist.id)
            }
        }
    }

    @MainActor
    private func mutatePlaylist(
        closeOnSuccess: Bool = true,
        _ operation: @escaping () async throws -> Void
    ) async {
        do {
            try await operation()
            playlistMutationError = nil
            if closeOnSuccess {
                playlistSheet = nil
            }
        } catch {
            playlistMutationError = error.localizedDescription
        }
    }

    private var segmentIndex: Int {
        (LibrarySegment.allCases.firstIndex(of: selectedSegment) ?? 0) + 1
    }
}

private enum LibraryRoute: Hashable {
    case collection(String)
    case creator(String)
    case playlist(String)
}

private enum PlaylistSheet: Identifiable, Hashable {
    case create
    case rename(String, String)
    case addItem(String)

    var id: String {
        switch self {
        case .create:
            "create"
        case .rename(let id, _):
            "rename-\(id)"
        case .addItem(let id):
            "add-\(id)"
        }
    }
}

private extension AuraPlaySearchSuggestion.Kind {
    var systemImage: String {
        switch self {
        case .title:
            "music.note"
        case .creator:
            "person.crop.square"
        case .collection:
            "rectangle.stack"
        }
    }
}

private extension AuraPlaySearchMatchSource {
    var title: String {
        switch self {
        case .local:
            "Local"
        case .semantic:
            "Semantic"
        case .localAndSemantic:
            "Both"
        }
    }
}

private extension String {
    var shortWalletDisplay: String {
        guard count > 12 else { return self }
        return "\(prefix(6))...\(suffix(4))"
    }
}
