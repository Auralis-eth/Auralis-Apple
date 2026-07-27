import Foundation

/// Source of truth for accessibility identifiers exposed to UI tests, VoiceOver
/// automation, and Voice Control labels.
///
/// New flows must register their primary controls, empty states, errors, and
/// destructive confirmations here before merge. See `AGENTS.md` for naming
/// conventions and ownership.
public enum A11yID {
    public enum Tabs {
        public static let home = "tab.home"
        public static let news = "tab.news"
        public static let gas = "tab.gas"
        public static let music = "tab.music"
        public static let receipts = "tab.receipts"
        public static let profile = "tab.profile"
        public static let search = "tab.search"
        public static let erc20 = "tab.erc20"
        public static let nftTokens = "tab.nftTokens"
    }

    public enum Home {
        public static let sparseState = "home.sparseState"
        public static let openAccounts = "home.accounts.open"
        public static let showImagePreview = "home.showImagePreview"
        public static let logout = "home.logout"
        public static let openSearch = "home.openSearch"
        public static let openReceipts = "home.openReceipts"
        public static let openNFTTokens = "home.openNFTTokens"

        public static func recentActivity(id: String) -> String {
            "home.recentActivity.\(id)"
        }
    }

    public enum Search {
        public static let root = "search.root"
        public static let queryField = "search.queryField"
        public static let assistantResults = "search.assistant.results"

        public static func scope(_ rawValue: String) -> String {
            "search.scope.\(rawValue)"
        }

        public static func suggestion(id: String) -> String {
            "search.suggestion.\(id)"
        }

        public static func match(id: String) -> String {
            "search.match.\(id)"
        }

        public static func assistantMatch(id: String) -> String {
            "search.assistant.match.\(id)"
        }

        public static func history(normalizedQuery: String) -> String {
            "search.history.\(normalizedQuery)"
        }
    }

    public enum ERC20 {
        public static let root = "erc20.root"
        public static let loading = "erc20.loading"
        public static let detailScreen = "erc20.detail.screen"
        public static let detailTitle = "erc20.detail.title"

        public static func row(id: String) -> String {
            "erc20.row.\(id)"
        }
    }

    public enum NFT {
        public static let detailScreen = "nft.detail.screen"
        public static let detailTitle = "nft.detail.title"
        public static let detailUnavailable = "nft.detail.unavailable"
        public static let collectionDetail = "nft.collection.detail"

        public static func collectionItem(id: String) -> String {
            "nft.collection.item.\(id)"
        }
    }

    public enum NFTTokens {
        public static let root = "nftTokens.root"

        public static func row(id: String) -> String {
            "nftTokens.row.\(id)"
        }
    }

    public enum ExternalLink {
        public static let confirmationSheet = "externalLink.confirmationSheet"
        public static let confirm = "externalLink.confirm"
        public static let cancel = "externalLink.cancel"
        public static let explorer = "externalLink.explorer"
        public static let openSea = "externalLink.openSea"
    }

    public enum Receipts {
        public static let root = "receipts.root"
        public static let detail = "receipts.detail"
        public static let detailUnavailable = "receipts.detail.unavailable"

        public static func row(id: String) -> String {
            "receipts.row.\(id)"
        }
    }

    public enum Accounts {
        public static func select(address: String) -> String {
            "accounts.select.\(address)"
        }

        public static func remove(address: String) -> String {
            "accounts.remove.\(address)"
        }
    }

    public enum AuraPlay {
        public static let unavailable = "auraplay.unavailable"
        public static let root = "auraplay.root"
        public static let librarySummary = "auraplay.library.summary"
        public static let librarySegmentPicker = "auraplay.library.segmentPicker"
        public static let libraryLayoutToggle = "auraplay.library.layoutToggle"
        public static let librarySearch = "auraplay.library.search"
        public static let libraryFilter = "auraplay.library.filter"
        public static let libraryFilterSheet = "auraplay.library.filter.sheet"
        public static let librarySort = "auraplay.library.sort"
        public static let searchRoot = "auraplay.search.root"
        public static let searchField = "auraplay.search.field"
        public static let searchClear = "auraplay.search.clear"
        public static let searchEmpty = "auraplay.search.empty"
        public static let searchLoading = "auraplay.search.loading"
        public static let searchResults = "auraplay.search.results"
        public static let searchNoResults = "auraplay.search.noResults"
        public static let searchFilteredEmpty = "auraplay.search.filteredEmpty"
        public static let searchDiagnostics = "auraplay.search.diagnostics"
        public static let searchMediaTypeFilter = "auraplay.search.filter.mediaType"
        public static let searchClearFilters = "auraplay.search.filter.clear"
        public static let searchClearRecents = "auraplay.search.recents.clear"
        public static let playlistPlayground = "auraplay.playground"
        public static let playlistPlaygroundPrompt = "auraplay.playground.prompt"
        public static let playlistPlaygroundGenerate = "auraplay.playground.generate"
        public static let playlistPlaygroundRegenerate = "auraplay.playground.regenerate"
        public static let playlistPlaygroundSave = "auraplay.playground.save"
        public static let playlistPlaygroundResults = "auraplay.playground.results"
        public static let recommendationsSavePlaylist = "auraplay.recommendations.savePlaylist"
        public static let libraryEmptyNoWallet = "auraplay.library.empty.noWallet"
        public static let libraryEmptySyncing = "auraplay.library.empty.syncing"
        public static let libraryEmptyNoPlayable = "auraplay.library.empty.noPlayable"
        public static let librarySyncBanner = "auraplay.library.syncBanner"
        public static let libraryIndexingPill = "auraplay.library.indexingPill"
        public static let semanticSearch = "auraplay.semantic.search"
        public static let semanticSearchRun = "auraplay.semantic.search.run"
        public static let semanticSearchClear = "auraplay.semantic.search.clear"
        public static let semanticResults = "auraplay.semantic.results"
        public static let collections = "auraplay.collections"
        public static let tracks = "auraplay.tracks"
        public static let queue = "auraplay.queue"
        public static let routeControls = "auraplay.routeControls"
        public static let cacheControls = "auraplay.cacheControls"
        public static let cacheStatus = "auraplay.cache.status"
        public static let cacheSaveOffline = "auraplay.cache.saveOffline"
        public static let cachePin = "auraplay.cache.pin"
        public static let cacheUnpin = "auraplay.cache.unpin"
        public static let cacheError = "auraplay.cache.error"
        public static let playbackToast = "auraplay.playback.toast"
        public static let miniPlayerCacheStatus = "auraplay.miniPlayer.cacheStatus"
        public static let miniPlayer = "auraplay.miniPlayer"
        public static let miniPlayerPlayPause = "auraplay.miniPlayer.playPause"
        public static let miniPlayerRestorePiP = "auraplay.miniPlayer.restorePiP"
        public static let audioTuning = "auraplay.audioTuning"
        public static let audioTuningEQPreset = "auraplay.audioTuning.eqPreset"
        public static let audioTuningNormalize = "auraplay.audioTuning.normalize"
        public static let audioTuningCrossfade = "auraplay.audioTuning.crossfade"
        public static let audioTuningCustomEQ = "auraplay.audioTuning.customEQ"
        public static let audioTuningDownloadOffline = "auraplay.audioTuning.downloadOffline"
        public static let settingsAudioTuning = "auraplay.settings.audioTuning"
        public static let settingsPlayback = "auraplay.settings.playback"
        public static let settingsShuffleDefault = "auraplay.settings.playback.shuffleDefault"
        public static let settingsRepeatDefault = "auraplay.settings.playback.repeatDefault"
        public static let settingsVideoSpeed = "auraplay.settings.playback.videoSpeed"
        public static let settingsStorage = "auraplay.settings.storage"
        public static let settingsCacheUsage = "auraplay.settings.storage.cacheUsage"
        public static let settingsCacheLimit = "auraplay.settings.storage.cacheLimit"
        public static let settingsClearCache = "auraplay.settings.storage.clearCache"
        public static let settingsDisconnectAllWallets = "auraplay.settings.privacy.disconnectAllWallets"
        public static let settingsIntelligence = "auraplay.settings.intelligence"
        public static let settingsSmartShuffle = "auraplay.settings.intelligence.smartShuffle"
        public static let settingsEmbeddingUnavailable = "auraplay.settings.intelligence.embeddingUnavailable"
        public static let visualizer = "auraplay.visualizer"
        public static let sharedSession = "auraplay.sharedSession"
        public static let videoWireframe = "auraplay.videoWireframe"
        public static let videoPlayer = "auraplay.video.player"
        public static let videoLoadSample = "auraplay.video.loadSample"
        public static let videoPlayback = "auraplay.video.playback"
        public static let videoStatus = "auraplay.video.status"
        public static let detailScreen = "auraplay.detail.screen"
        public static let detailTitle = "auraplay.detail.title"
        public static let detailPlayback = "auraplay.detail.playback"
        public static let detailUnavailable = "auraplay.detail.unavailable"
        public static let collectionDetail = "auraplay.collection.detail"
        public static let collectionDetailEmpty = "auraplay.collection.detail.empty"
        public static let creatorProfile = "auraplay.creator.profile"
        public static let creatorProfileEmpty = "auraplay.creator.profile.empty"
        public static let creators = "auraplay.creators"
        public static let playlists = "auraplay.playlists"
        public static let addToPlaylistSheet = "auraplay.playlists.addToPlaylist"
        public static let playlistNameEditor = "auraplay.playlists.nameEditor"
        public static let playerSheet = "auraplay.player.sheet"
        public static let playerDismiss = "auraplay.player.dismiss"
        public static let playerArtwork = "auraplay.player.artwork"
        public static let playerVideoSurface = "auraplay.player.videoSurface"
        public static let playerPlayPause = "auraplay.player.playPause"
        public static let playerPrevious = "auraplay.player.previous"
        public static let playerNext = "auraplay.player.next"
        public static let playerScrubber = "auraplay.player.scrubber"
        public static let playerElapsedTime = "auraplay.player.elapsedTime"
        public static let playerTrailingTime = "auraplay.player.trailingTime"
        public static let playerUpNext = "auraplay.player.upNext"
        public static let playerShuffle = "auraplay.player.shuffle"
        public static let playerRepeat = "auraplay.player.repeat"
        public static let playerAudioControls = "auraplay.player.audioControls"
        public static let playerVideoControls = "auraplay.player.videoControls"
        public static let playerPiP = "auraplay.player.pip"
        public static let playerAirPlay = "auraplay.player.airplay"
        public static let playerSubtitles = "auraplay.player.subtitles"
        public static let playerSpeed = "auraplay.player.speed"
        public static let playerShare = "auraplay.player.share"
        public static let playerViewOnExplorer = "auraplay.player.viewOnExplorer"
        public static let playerCopyContract = "auraplay.player.copyContract"
        public static let provenancePanel = "auraplay.provenance.panel"
        public static let provenanceCopyContract = "auraplay.provenance.copyContract"
        public static let provenanceExplorerLink = "auraplay.provenance.explorerLink"
        public static let playerSkipBack10 = "auraplay.player.skipBack10"
        public static let playerSkipForward10 = "auraplay.player.skipForward10"
        public static let playerCopyToast = "auraplay.player.copyToast"
        public static let collectionPlayAll = "auraplay.collection.playAll"
        public static let walletPicker = "auraplay.walletPicker"
        public static let walletPickerConnect = "auraplay.walletPicker.connect"
        public static let walletPickerProviderList = "auraplay.walletPicker.providers"
        public static let walletPickerQR = "auraplay.walletPicker.qr"
        public static let walletPickerCancel = "auraplay.walletPicker.cancel"
        public static let walletPickerError = "auraplay.walletPicker.error"
        public static let walletPickerSignDenied = "auraplay.walletPicker.signDenied"
        public static let walletPickerRemoveConfirmation = "auraplay.walletPicker.removeConfirmation"

        public static func collectionTrack(id: String) -> String {
            "auraplay.collection.track.\(id)"
        }

        public static func trackRow(id: String) -> String {
            "auraplay.track.\(id)"
        }

        public static func walletPickerProvider(id: String) -> String {
            "auraplay.walletPicker.provider.\(sanitizedIdentifierComponent(id))"
        }

        public static func walletPickerRow(address: String) -> String {
            "auraplay.walletPicker.row.\(sanitizedIdentifierComponent(address))"
        }

        public static func libraryCell(id: String) -> String {
            "auraplay.library.cell.\(id)"
        }

        public static func semanticResult(id: String) -> String {
            "auraplay.semantic.result.\(id)"
        }

        public static func searchSuggestion(id: String) -> String {
            "auraplay.search.suggestion.\(id)"
        }

        public static func searchRecent(query: String) -> String {
            "auraplay.search.recent.\(sanitizedIdentifierComponent(query))"
        }

        public static func searchSuggested(query: String) -> String {
            "auraplay.search.suggested.\(sanitizedIdentifierComponent(query))"
        }

        public static func searchResult(id: String) -> String {
            "auraplay.search.result.\(id)"
        }

        public static func audioTuningCustomEQBand(index: Int) -> String {
            "auraplay.audioTuning.customEQ.band.\(index)"
        }

        public static func collectionRow(id: String) -> String {
            "auraplay.collection.\(id)"
        }

        public static func creatorRow(id: String) -> String {
            "auraplay.creator.\(id)"
        }

        public static func playlistRow(id: String) -> String {
            "auraplay.playlist.\(id)"
        }

        public static func playlistItem(id: String) -> String {
            "auraplay.playlist.item.\(id)"
        }

        public static func videoItem(id: String) -> String {
            "auraplay.video.item.\(id)"
        }

        private static func sanitizedIdentifierComponent(_ value: String) -> String {
            value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: ".")
        }
    }

    public enum RouteError {
        public static let screen = "routeError.screen"
        public static let dismiss = "routeError.dismiss"
    }

    public enum ContextInspector {
        public static let latestReceipt = "contextInspector.receipt.latest"
    }
}
