import Foundation

/// Source of truth for accessibility identifiers exposed to UI tests, VoiceOver
/// automation, and Voice Control labels.
///
/// New flows must register their primary controls, empty states, errors, and
/// destructive confirmations here before merge. See `AGENTS.md` for naming
/// conventions and ownership.
public enum A11yID {
    public enum Settings {
        public static let ritualNotificationStatus = "settings.ritualNotifications.status"
        public static let ritualNotificationEnable = "settings.ritualNotifications.enable"
        public static let ritualNotificationError = "settings.ritualNotifications.error"
    }

    public enum Social {
        public static let root = "social.root"
        public static let generateInvite = "social.invite.generate"
        public static let shareInvite = "social.invite.share"
        public static let inviteCode = "social.invite.code"
        public static let joinCodeField = "social.join.codeField"
        public static let join = "social.join.submit"
        public static let scanInvite = "social.join.scan"
        public static let status = "social.status"
        public static let error = "social.error"
    }

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
        public static let missionControl = "tab.missionControl"
    }

    /// Mission Control operator console (Ops tab). This is the single source of truth used by both
    /// production views and UI automation.
    public enum MissionControl {
        /// The toolbar section `Picker`. Distinct from ``sectionList``: both drive the same selection,
        /// so sharing one identifier made every non-`buttons` query for it ambiguous.
        public static let sectionPicker = "missionControl.sectionPicker"
        /// The `NavigationSplitView` sidebar section list — the compact-width navigation entry point.
        public static let sectionList = "missionControl.sectionList"
        public static let pauseToggle = "missionControl.pauseToggle"
        public static let modeSection = "missionControl.modeSection"
        public static let timeline = "missionControl.timeline"
        public static let timelineEmpty = "missionControl.timeline.empty"
        public static func workflowStopButton(_ correlationID: String) -> String { "missionControl.timeline.stop.\(correlationID)" }
        public static let timelineAccountFilter = "missionControl.timeline.accountFilter"
        public static let timelinePlaybookFilter = "missionControl.timeline.playbookFilter"
        public static func timelineReasoning(_ correlationID: String) -> String { "missionControl.timeline.reasoning.\(correlationID)" }
        public static let activityFeed = "missionControl.activityFeed"
        public static let activityFeedEmpty = "missionControl.activityFeed.empty"
        public static let homeFreshness = "missionControl.home.freshness"
        public static let homeRevoke = "missionControl.home.revoke"
        public static let modeSurfaces = "missionControl.mode.surfaces"
        public static let sessions = "missionControl.sessions"
        public static let sessionsOpen = "missionControl.sessions.open"
        public static let sessionsEmpty = "missionControl.sessions.empty"
        public static func sessionRow(_ id: String) -> String { "missionControl.sessions.row.\(id)" }
        public static let sessionEnd = "missionControl.sessions.end"
        public static let sessionParticipantName = "missionControl.sessions.participant.name"
        public static let sessionParticipantRole = "missionControl.sessions.participant.role"
        public static let sessionParticipantAdd = "missionControl.sessions.participant.add"
        public static let sessionShareReceipt = "missionControl.sessions.share.receipt"
        public static let sessionShareArtifact = "missionControl.sessions.share.artifact"
        public static let sessionShareWorkflow = "missionControl.sessions.share.workflow"
        public static let sessionAgentContextTitle = "missionControl.sessions.agentContext.title"
        public static let sessionAgentContextSummary = "missionControl.sessions.agentContext.summary"
        public static let sessionShareAgentContext = "missionControl.sessions.share.agentContext"
        public static func sessionAgentContextRow(_ id: String) -> String { "missionControl.sessions.agentContext.row.\(id)" }
        public static let sessionSyncStatus = "missionControl.sessions.sync.status"
        public static let sessionQueueStatus = "missionControl.sessions.queue.status"
        public static let sessionRitualStatus = "missionControl.sessions.ritual.status"
        public static let ritualsEmpty = "missionControl.rituals.empty"
        public static func ritualRow(_ id: String) -> String { "missionControl.rituals.row.\(id)" }
        public static func ritualEnabled(_ id: String) -> String { "missionControl.rituals.enabled.\(id)" }
        public static func ritualRun(_ id: String) -> String { "missionControl.rituals.run.\(id)" }
        public static func ritualStatus(_ id: String) -> String { "missionControl.rituals.status.\(id)" }
        public static let sessionApprovalRequiredCount = "missionControl.sessions.approval.requiredCount"
        public static let sessionApprovalOpen = "missionControl.sessions.approval.open"
        public static func sessionApprovalApprove(_ id: String) -> String { "missionControl.sessions.approval.approve.\(id)" }
        public static func sessionApprovalReject(_ id: String) -> String { "missionControl.sessions.approval.reject.\(id)" }
        public static let sessionModel = "missionControl.session.model"
        public static let sessionInference = "missionControl.session.inference"
        public static let sessionTokens = "missionControl.session.tokens"
        public static let sessionModelHops = "missionControl.session.modelHops"
        public static let context = "missionControl.context"
        public static let approvals = "missionControl.approvals"
        public static let approvalsEmpty = "missionControl.approvals.empty"
        public static let policyCards = "missionControl.approvals.policyCards"
        public static func approvalRisk(_ id: String) -> String { "missionControl.approvals.risk.\(id)" }
        public static let approvalPlanLink = "missionControl.approvals.planLink"
        public static let approvalReceiptLink = "missionControl.approvals.receiptLink"
        public static let approvalArtifactLink = "missionControl.approvals.artifactLink"
        public static let proposalSimulation = "missionControl.proposal.simulation"
        public static let proposalSimulationFreshness = "missionControl.proposal.simulation.freshness"
        public static let approvalPersistenceError = "missionControl.approvals.persistenceError"
        public static let dataQualityWarning = "missionControl.dataQuality.warning"
        public static let capabilities = "missionControl.capabilities"
        public static let capabilitiesEmpty = "missionControl.capabilities.empty"
        public static let capabilityGrantActorID = "missionControl.capabilities.grant.actorID"
        public static let capabilityGrantReason = "missionControl.capabilities.grant.reason"
        public static let capabilityGrantButton = "missionControl.capabilities.grant.button"
        public static let capabilityRestrictionActorID = "missionControl.capabilities.restriction.actorID"
        public static let capabilityRestrictionReason = "missionControl.capabilities.restriction.reason"
        public static let capabilityDenyButton = "missionControl.capabilities.deny.button"
        public static let pausedBanner = "missionControl.pausedBanner"
        public static let resumeButton = "missionControl.resumeButton"
        public static let receiptsBrowser = "missionControl.receipts.browser"
        public static let receiptsBrowserEmpty = "missionControl.receipts.browser.empty"
        public static let receiptsScopeFilter = "missionControl.receipts.scopeFilter"
        public static let receiptsOutcomeFilter = "missionControl.receipts.outcomeFilter"
        public static let receiptDetail = "missionControl.receipt.detail"
        public static let receiptArtifactLink = "missionControl.receipt.artifactLink"
        public static let receiptArtifactID = "missionControl.receipt.artifactID"
        /// Per-entry actor attribution on a session's worklog trace (P0.5-602).
        public static let worklogAttribution = "missionControl.worklog.attribution"
        public static let worklogExport = "missionControl.worklog.export"
        public static let worklogWorkflowExport = "missionControl.worklog.workflowExport"
        public static let worklogDegraded = "missionControl.worklog.degraded"
        public static let reportCardTraceHealth = "missionControl.reportCard.traceHealth"
        public static let improvementRecommendation = "missionControl.improvement.recommendation"
        public static let playbooks = "missionControl.playbooks"
        public static let playbookCreate = "missionControl.playbooks.create"
        public static let playbookDetail = "missionControl.playbook.detail"
        public static let playbookPersistenceError = "missionControl.playbook.persistenceError"
        /// The sticky degraded-audit-evidence banner raised when a runtime receipt could not be
        /// written, and its explicit acknowledgement control.
        public static let receiptPersistenceError = "missionControl.receipt.persistenceError"
        public static let receiptPersistenceAcknowledge = "missionControl.receipt.persistenceError.acknowledge"
        /// The banner raised when a coordination store quarantined an unreadable payload and has
        /// stopped accepting writes, and its explicit discard control — the only way out.
        public static let coordinationPersistenceError = "missionControl.coordination.persistenceError"
        public static let coordinationPersistenceDiscard = "missionControl.coordination.persistenceError.discard"
        public static let routines = "missionControl.routines"
        public static let routinesEmpty = "missionControl.routines.empty"
        public static let performance = "missionControl.performance"
        public static let performanceEmpty = "missionControl.performance.empty"
        public static let performanceRunReceiptLink = "missionControl.performance.runReceiptLink"
        public static let performanceFailuresEmpty = "missionControl.performance.failures.empty"
        public static let performanceFailureReceiptLink = "missionControl.performance.failureReceiptLink"
        public static let performanceFailurePattern = "missionControl.performance.failurePattern"
        public static func performanceHealthRow(_ playbookID: String) -> String { "missionControl.performance.health.\(playbookID)" }
        public static let reportCards = "missionControl.reportCards"
        public static let reportCardsEmpty = "missionControl.reportCards.empty"
        public static let reportCard = "missionControl.reportCards.card"
        public static let reportCardShortfall = "missionControl.reportCards.shortfall"
        public static let operators = "missionControl.operators"
        public static let operatorsEmpty = "missionControl.operators.empty"
        public static func operatorRun(_ toolID: String) -> String { "missionControl.operators.run.\(toolID)" }
        public static func operatorOutcome(_ toolID: String) -> String { "missionControl.operators.outcome.\(toolID)" }
        public static let operatorIdentityScope = "missionControl.operators.identityScope"
        public static let operatorWatchInput = "missionControl.operators.watch.input"
        public static let operatorWatchAdd = "missionControl.operators.watch.add"
        public static let operatorWatchlistEmpty = "missionControl.operators.watch.empty"
        public static let operatorEscalate = "missionControl.operators.escalate"
        public static let artifacts = "missionControl.artifacts"
        public static func artifactRow(_ id: String) -> String { "missionControl.artifacts.row.\(id)" }
        public static let artifactsEmpty = "missionControl.artifacts.empty"
        public static let artifactsTypeFilter = "missionControl.artifacts.typeFilter"
        public static let artifactsRecencyFilter = "missionControl.artifacts.recencyFilter"
        public static let artifactsWorkflowFilter = "missionControl.artifacts.workflowFilter"
        public static let artifactsAccountFilter = "missionControl.artifacts.accountFilter"
        public static let artifactsHistoryScope = "missionControl.artifacts.historyScope"
        public static let artifactsPlaybookObjects = "missionControl.artifacts.playbookObjects"
        public static func artifactPlaybookObject(_ id: String) -> String { "missionControl.artifacts.playbook.\(id)" }
        public static let artifactDetail = "missionControl.artifact.detail"
        public static let artifactApprove = "missionControl.artifact.approve"
        public static let artifactExport = "missionControl.artifact.export"
        public static let artifactSupersede = "missionControl.artifact.supersede"
        public static let mode = "missionControl.mode"
        public static let modePicker = "missionControl.mode.picker"
    }

    public enum TrustedUI {
        public static let approvalSurface = "trustedui.approval.surface"
        public static let approvalApprove = "trustedui.approval.approve"
        public static let approvalDeny = "trustedui.approval.deny"
        public static let approvalDefer = "trustedui.approval.defer"
        public static let approvalSubmitted = "trustedui.approval.submitted"
        public static let draftEditor = "trustedui.draft.editor"
        public static let draftSave = "trustedui.draft.save"
        public static let permissionCard = "trustedui.permission.card"
        public static let receiptCard = "trustedui.receipt.card"
        public static let contextBundleCard = "trustedui.contextbundle.card"
        public static let unavailable = "trustedui.unavailable"
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
        public static let detailPostflight = "receipts.detail.postflight"
        public static let detailReadable = "receipts.detail.readable"
        public static let detailTimeline = "receipts.detail.timeline"
        public static let detailArtifacts = "receipts.detail.artifacts"

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
        public static let autoOrganizationOpen = "auraplay.autoOrganization.open"
        public static let autoOrganizationSheet = "auraplay.autoOrganization.sheet"
        public static let autoOrganizationRun = "auraplay.autoOrganization.run"
        public static let autoOrganizationStatus = "auraplay.autoOrganization.status"
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
