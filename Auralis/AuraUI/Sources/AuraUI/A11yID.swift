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

        public static func match(id: String) -> String {
            "search.match.\(id)"
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
        public static let librarySearch = "auraplay.library.search"
        public static let libraryFilter = "auraplay.library.filter"
        public static let librarySort = "auraplay.library.sort"
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
        public static let audioTuning = "auraplay.audioTuning"
        public static let audioTuningEQPreset = "auraplay.audioTuning.eqPreset"
        public static let audioTuningNormalize = "auraplay.audioTuning.normalize"
        public static let audioTuningCrossfade = "auraplay.audioTuning.crossfade"
        public static let audioTuningCustomEQ = "auraplay.audioTuning.customEQ"
        public static let audioTuningDownloadOffline = "auraplay.audioTuning.downloadOffline"
        public static let settingsAudioTuning = "auraplay.settings.audioTuning"
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

        public static func collectionTrack(id: String) -> String {
            "auraplay.collection.track.\(id)"
        }

        public static func trackRow(id: String) -> String {
            "auraplay.track.\(id)"
        }

        public static func audioTuningCustomEQBand(index: Int) -> String {
            "auraplay.audioTuning.customEQ.band.\(index)"
        }

        public static func collectionRow(id: String) -> String {
            "auraplay.collection.\(id)"
        }

        public static func videoItem(id: String) -> String {
            "auraplay.video.item.\(id)"
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
