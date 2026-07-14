import AuraPlayMediaCore
import AuraPlayAudioEngine
import AuraPlayVideoEngine
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import AuraUI
import AVFoundation
import MusicFeature
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AuraPlayVideoWireframeView: View {
    let currentAccount: EOAccount?
    let currentChain: Chain
    let auraPlayModelContainer: ModelContainer?
    let playbackRuntime: AuraPlayPlaybackRuntime?
    let restoreVideoRoute: @MainActor () -> Bool

    @Query private var allLibraryItems: [MusicLibraryItem]

    @State private var controller = VideoPlayerController()
    @State private var mediaSessionManager = SystemVideoMediaSessionManager()
    @State private var nowPlayingPublisher = NowPlayingPublisher()
    @State private var urlResolver = URLResolver()
    @State private var remoteControlBridge = AuraPlayVideoRemoteControlBridge()
    @State private var subtitleTrackManager = SubtitleTrackManager()
    @State private var trackManager = VideoMediaTrackManager()
    @State private var videoIntegrationCoordinator: VideoPlaybackIntegrationCoordinator?
    @State private var pictureInPictureController: PictureInPictureController?
    @State private var selectedMedia: AuraPlayableMediaItem?
    @State private var playbackState: VideoPlaybackState = .idle
    @State private var statusMessage = "Select a video from the current wallet scope."
    @State private var currentSeconds = 0.0
    @State private var durationSeconds = 1.0
    @State private var isDragging = false
    @State private var selectedSpeed: PlaybackSpeedOption = PlaybackSpeedController().storedSpeed
    @State private var lastErrorMessage: String?
    @State private var isExternalPlaybackActive = false
    @State private var availableSubtitles: [SubtitleTrack] = []
    @State private var selectedSubtitleID: String?
    @State private var availableAudioTracks: [VideoAudioTrack] = []
    @State private var selectedAudioTrackID: String?
    @State private var audioDescriptionTracks: [AudioDescriptionTrack] = []
    @State private var selectedAudioDescriptionTrackID: String?
    @State private var chapters: [VideoChapter] = []
    @State private var capabilities: VideoPlaybackCapabilities?
    @State private var presentationInfo: VideoPresentationInfo?
    @State private var isHDRContent = false
    @State private var deviceSupportsHDRDisplay = false
    @State private var pipState: PiPState = .inactive
    @State private var showFullscreen = false
    @State private var resumePosition: StoredVideoPlaybackPosition?
    @State private var videoZoomScale = 1.0
    @State private var posterImages: [String: PlatformImage] = [:]
    @State private var posterCache = InMemoryVideoArtworkCache()
    @State private var fallbackTask: Task<Void, Never>?
    @State private var videoToast: VideoPlaybackToast?

    init(
        currentAccount: EOAccount?,
        currentChain: Chain,
        auraPlayModelContainer: ModelContainer?,
        playbackRuntime: AuraPlayPlaybackRuntime?,
        restoreVideoRoute: @escaping @MainActor () -> Bool = { true }
    ) {
        self.currentAccount = currentAccount
        self.currentChain = currentChain
        self.auraPlayModelContainer = auraPlayModelContainer
        self.playbackRuntime = playbackRuntime
        self.restoreVideoRoute = restoreVideoRoute

        let sortDescriptors: [SortDescriptor<MusicLibraryItem>] = [
            SortDescriptor(\MusicLibraryItem.normalizedCollectionKey),
            SortDescriptor(\MusicLibraryItem.normalizedArtistKey),
            SortDescriptor(\MusicLibraryItem.normalizedTitleKey),
            SortDescriptor(\MusicLibraryItem.id)
        ]
        _allLibraryItems = Query(sort: sortDescriptors)
    }

    @ViewBuilder
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    playerSurface
                    transportCard
                    videoLibraryCard
                    optionsCard
                    mediaTracksCard
                    chaptersCard
                    capabilityStatusCard
                }
                .padding()
            }

            if let videoToast {
                VideoPlaybackToastView(toast: videoToast)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: videoToast.id) {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if self.videoToast?.id == videoToast.id {
                            self.videoToast = nil
                        }
                    }
            }
        }
        .background(Color.background)
        .navigationTitle("AuraPlay Video")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.AuraPlay.videoWireframe)
        .task {
            await observeVideoEvents()
        }
        .onDisappear {
            persistCurrentPosition()
            playbackRuntime?.auraPlayRegisterVideoRemoteControls(nil)
            playbackRuntime?.auraPlayVideoPlaybackStopped()
            fallbackTask?.cancel()
            fallbackTask = nil
            Task {
                await videoIntegrationCoordinator?.stop()
                videoIntegrationCoordinator = nil
            }
            updateOrientationLock(for: nil)
        }
        .task(id: scopedVideoPosterSignature) {
            await generateMissingPosterFrames()
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            fullscreenPlayer
        }
    }

    private var scopedVideoItems: [MusicLibraryItem] {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address) ?? ""
        let chainRawValue = currentChain.rawValue
        return allLibraryItems.filter { item in
            item.accountAddressRawValue == normalizedAccountAddress
                && item.networkRawValue == chainRawValue
                && item.isPlaybackReady
                && item.isVideoCapable
        }
    }

    private var playerSurface: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                PlayerContainerView(
                    player: controller.player,
                    videoGravity: videoGravity,
                    onLayerReady: configurePictureInPicture
                )
                .scaleEffect(videoZoomScale)
                .aspectRatio(playerAspectRatio, contentMode: .fit)
                .background(.black)

                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { value in
                                handleDoubleTapSeek(at: value.location, in: geometry.size)
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                videoZoomScale = min(max(value, 1), 3)
                            }
                            .onEnded { value in
                                videoZoomScale = min(max(value, 1), 3)
                            }
                    )

                playerStateOverlay
                playerChromeOverlay
            }
        }
        .aspectRatio(playerAspectRatio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityLabel("Video player")
        .accessibilityValue(accessibilityPlaybackValue)
        .accessibilityIgnoresInvertColors()
        .accessibilityIdentifier(A11yID.AuraPlay.videoPlayer)
    }

    @ViewBuilder
    private var playerStateOverlay: some View {
        switch playbackState {
        case .idle:
            VideoOverlayStatus(
                title: "No Video Loaded",
                message: scopedVideoItems.isEmpty
                    ? "No video-capable media is indexed for this wallet and chain."
                    : "Select a video below to begin playback.",
                systemImage: "play.rectangle"
            )
        case .loading, .buffering:
            VideoOverlayStatus(
                title: playbackState == .buffering ? "Buffering" : "Loading",
                message: statusMessage,
                systemImage: "hourglass",
                showsProgress: true
            )
        case .failed:
            VideoOverlayStatus(
                title: "Video Unavailable",
                message: lastErrorMessage ?? statusMessage,
                systemImage: "exclamationmark.triangle"
            )
        default:
            EmptyView()
        }
    }

    private var playerChromeOverlay: some View {
        LiquidGlassOverlayContainer {
            HStack(spacing: 10) {
                Button(playbackButtonTitle, systemImage: playbackButtonSystemImage, action: togglePlayback)
                    .disabled(!canTogglePlayback)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(playbackButtonTitle)

                Text("\(timeString(currentSeconds)) / \(timeString(durationSeconds))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()

                if showsHDRBadge {
                    Text("HDR")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.24), in: Capsule())
                        .accessibilityLabel("HDR video")
                }

                if videoZoomScale > 1.01 {
                    Button("Reset Zoom", systemImage: "arrow.down.right.and.arrow.up.left") {
                        videoZoomScale = 1
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Reset video zoom")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var transportCard: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(selectedMedia?.metadata.title ?? "Playback", systemImage: "play.circle")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Text(statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(A11yID.AuraPlay.videoStatus)

                if let resumePosition {
                    Button("Resume at \(timeString(Double(resumePosition.positionMilliseconds) / 1000))", systemImage: "gobackward") {
                        Task {
                            await controller.seek(to: Double(resumePosition.positionMilliseconds) / 1000, kind: .resume)
                            controller.play()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                ViewThatFits(in: .horizontal) {
                    HStack {
                        playbackButton
                        skipBackwardButton
                        skipForwardButton
                        previousButton
                        nextButton
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        playbackButton
                        HStack {
                            skipBackwardButton
                            skipForwardButton
                            previousButton
                            nextButton
                        }
                    }
                }
                .buttonStyle(.bordered)

                Slider(
                    value: Binding(
                        get: { currentSeconds },
                        set: { currentSeconds = $0 }
                    ),
                    in: 0...max(1, durationSeconds),
                    onEditingChanged: seekEditingChanged
                )
                .disabled(!canSeek)
                .accessibilityLabel("Video position")
                .accessibilityValue("\(timeString(currentSeconds)) of \(timeString(durationSeconds))")

                HStack {
                    Text(timeString(currentSeconds))
                    Spacer()
                    Text(timeString(durationSeconds))
                }
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var videoLibraryCard: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Video Library", systemImage: "film.stack")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                VideoLibraryList(
                    rows: scopedVideoItems.map { VideoLibraryPresentationItem(item: $0, posterImage: posterImages[$0.id]) },
                    selectedID: selectedMedia?.id,
                    load: { itemID in
                        Task { await loadVideo(id: itemID) }
                    }
                )
            }
        }
    }

    private var optionsCard: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Playback Options", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Picker("Speed", selection: $selectedSpeed) {
                    ForEach(PlaybackSpeedOption.allCases) { speed in
                        Text(speed.displayLabel).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!hasCurrentItem)
                .onChange(of: selectedSpeed) { _, speed in
                    try? PlaybackSpeedController().setSpeed(speed, on: controller.player)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        routePickerAndStatus
                        platformButtons
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        routePickerAndStatus
                        platformButtons
                    }
                }
            }
        }
    }

    private var routePickerAndStatus: some View {
        HStack(alignment: .center, spacing: 12) {
            VideoRoutePickerView()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay") // [VERIFY] opens system video route picker.

            VStack(alignment: .leading, spacing: 4) {
                Text(isExternalPlaybackActive ? "AirPlay active" : "Local playback")
                    .font(.subheadline.weight(.semibold))
                Text("External routes use the system picker and active player item.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var platformButtons: some View {
        HStack {
            Button(pipButtonTitle, systemImage: "pip") {
                togglePictureInPicture()
            }
            .disabled(!canUsePictureInPicture)

            Button("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right") {
                showFullscreen = true
            }
            .disabled(!hasCurrentItem)
        }
        .buttonStyle(.bordered)
    }

    private var mediaTracksCard: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Tracks and Captions", systemImage: "captions.bubble")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ViewThatFits(in: .horizontal) {
                    HStack {
                        if showsSubtitleToggle {
                            subtitleMenu
                        }
                        audioMenu
                        if !audioDescriptionTracks.isEmpty {
                            audioDescriptionMenu
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        if showsSubtitleToggle {
                            subtitleMenu
                        }
                        audioMenu
                        if !audioDescriptionTracks.isEmpty {
                            audioDescriptionMenu
                        }
                    }
                }

                if audioDescriptionTracks.isEmpty {
                    VideoCapabilityRow(
                        title: "Audio descriptions",
                        message: "No audio-description tracks are exposed by this media item.",
                        systemImage: "speaker.wave.2",
                        status: "None"
                    )
                } else if let selectedAudioDescriptionTrack {
                    VideoCapabilityRow(
                        title: "Audio descriptions",
                        message: "\(selectedAudioDescriptionTrack.displayName) is selected.",
                        systemImage: "speaker.wave.2",
                        status: "On"
                    )
                } else {
                    VideoCapabilityRow(
                        title: "Audio descriptions",
                        message: "\(audioDescriptionTracks.count) audio-description track(s) available.",
                        systemImage: "speaker.wave.2",
                        status: "Available"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var chaptersCard: some View {
        if !chapters.isEmpty {
            AuraSurfaceCard(style: .regular, cornerRadius: 20, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Chapters", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(chapters) { chapter in
                        Button {
                            Task {
                                await controller.seek(to: chapter.startSeconds, kind: .skip)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chapter.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(timeString(chapter.startSeconds))
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.textSecondary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var capabilityStatusCard: some View {
        AuraSurfaceCard(style: .regular, cornerRadius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Media Capabilities", systemImage: "checklist")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                VideoCapabilityRow(
                    title: "Source",
                    message: selectedMedia == nil
                        ? "Select indexed wallet media to load a video item."
                        : "Loaded from indexed wallet media through the AuraPlay URL resolver.",
                    systemImage: "play.rectangle",
                    status: selectedMedia == nil ? "Waiting" : "Loaded"
                )

                VideoCapabilityRow(
                    title: "Captions",
                    message: availableSubtitles.isEmpty ? "No subtitle tracks found." : "\(availableSubtitles.count) subtitle track(s) available.",
                    systemImage: "captions.bubble",
                    status: availableSubtitles.isEmpty ? "None" : "Available"
                )

                VideoCapabilityRow(
                    title: "Format",
                    message: formatCapabilityMessage,
                    systemImage: "sparkles.tv",
                    status: formatCapabilityStatus
                )

                VideoCapabilityRow(
                    title: "Aspect",
                    message: aspectCapabilityMessage,
                    systemImage: "aspectratio",
                    status: aspectCapabilityStatus
                )

                if showsHDRBadge {
                    VideoCapabilityRow(
                        title: "HDR",
                        message: hdrCapabilityMessage,
                        systemImage: "sun.max",
                        status: hdrCapabilityStatus
                    )
                }

                if capabilities?.isHighFrameRate == true {
                    VideoCapabilityRow(
                        title: "High frame rate",
                        message: "This asset reports a frame rate of 48 fps or higher.",
                        systemImage: "speedometer",
                        status: "HFR"
                    )
                }
            }
        }
    }

    private var fullscreenPlayer: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            PlayerContainerView(player: controller.player, videoGravity: .resizeAspect)
                .scaleEffect(videoZoomScale)
                .ignoresSafeArea()
                .accessibilityLabel("Fullscreen video player")
                .accessibilityValue(accessibilityPlaybackValue)

            LiquidGlassOverlayContainer {
                HStack(spacing: 10) {
                    Button("Done", systemImage: "xmark") {
                        showFullscreen = false
                    }
                    Button(playbackButtonTitle, systemImage: playbackButtonSystemImage, action: togglePlayback)
                        .disabled(!canTogglePlayback)
                    Text("\(timeString(currentSeconds)) / \(timeString(durationSeconds))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .padding()
        }
    }

    private var playbackButton: some View {
        Button(playbackButtonTitle, systemImage: playbackButtonSystemImage, action: togglePlayback)
            .disabled(!canTogglePlayback)
            .accessibilityIdentifier(A11yID.AuraPlay.videoPlayback)
    }

    private var skipBackwardButton: some View {
        Button("15", systemImage: "gobackward.15") {
            Task { await controller.seek(to: max(0, currentSeconds - 15), kind: .skip) }
        }
        .disabled(!canSeek)
        .accessibilityLabel("Skip backward 15 seconds")
    }

    private var skipForwardButton: some View {
        Button("15", systemImage: "goforward.15") {
            Task { await controller.seek(to: min(durationSeconds, currentSeconds + 15), kind: .skip) }
        }
        .disabled(!canSeek)
        .accessibilityLabel("Skip forward 15 seconds")
    }

    private var previousButton: some View {
        Button("Previous", systemImage: "backward.fill") {
            Task { await loadAdjacentVideo(offset: -1) }
        }
        .disabled(!canLoadAdjacentVideo(offset: -1))
    }

    private var nextButton: some View {
        Button("Next", systemImage: "forward.fill") {
            Task { await loadAdjacentVideo(offset: 1) }
        }
        .disabled(!canLoadAdjacentVideo(offset: 1))
    }

    private var subtitleMenu: some View {
        Menu {
            Button("Off") {
                Task { await selectSubtitle(nil) }
            }
            ForEach(availableSubtitles) { track in
                Button(track.displayName) {
                    Task { await selectSubtitle(track) }
                }
            }
        } label: {
            Label(selectedSubtitleTitle, systemImage: "captions.bubble")
        }
        .disabled(!hasCurrentItem)
        .buttonStyle(.bordered)
    }

    private var showsSubtitleToggle: Bool {
        !availableSubtitles.isEmpty || !audioDescriptionTracks.isEmpty
    }

    private var audioMenu: some View {
        Menu {
            Button("Default") {
                Task { await selectAudioTrack(nil) }
            }
            ForEach(availableAudioTracks) { track in
                Button(track.displayName + (track.isDefault ? " (Default)" : "")) {
                    Task { await selectAudioTrack(track) }
                }
            }
        } label: {
            Label(selectedAudioTrackTitle, systemImage: "speaker.wave.2")
        }
        .disabled(!hasCurrentItem)
        .buttonStyle(.bordered)
    }

    private var audioDescriptionMenu: some View {
        Menu {
            Button("Off") {
                Task { await selectAudioDescriptionTrack(nil) }
            }
            ForEach(audioDescriptionTracks) { track in
                Button(track.displayName) {
                    Task { await selectAudioDescriptionTrack(track) }
                }
            }
        } label: {
            Label(selectedAudioDescriptionTitle, systemImage: "speaker.badge.exclamationmark")
        }
        .disabled(!hasCurrentItem)
        .buttonStyle(.bordered)
    }

    private var selectedSubtitleTitle: String {
        guard let selectedSubtitleID,
              let track = availableSubtitles.first(where: { $0.id == selectedSubtitleID }) else {
            return "Subtitles Off"
        }
        return track.displayName
    }

    private var selectedAudioTrackTitle: String {
        guard let selectedAudioTrackID,
              let track = availableAudioTracks.first(where: { $0.id == selectedAudioTrackID }) else {
            return "Default Audio"
        }
        return track.displayName
    }

    private var selectedAudioDescriptionTrack: AudioDescriptionTrack? {
        guard let selectedAudioDescriptionTrackID else { return nil }
        return audioDescriptionTracks.first { $0.id == selectedAudioDescriptionTrackID }
    }

    private var selectedAudioDescriptionTitle: String {
        guard let selectedAudioDescriptionTrack else {
            return "Audio Descriptions Off"
        }
        return selectedAudioDescriptionTrack.displayName
    }

    private var playbackButtonTitle: String {
        playbackState == .playing ? "Pause" : playbackState == .ended ? "Replay" : "Play"
    }

    private var playbackButtonSystemImage: String {
        playbackState == .playing ? "pause.fill" : "play.fill"
    }

    private var pipButtonTitle: String {
        switch pipState {
        case .active, .starting:
            "Stop PiP"
        case .unsupported:
            "PiP Unavailable"
        case .inactive, .stopping:
            "Picture in Picture"
        }
    }

    private var canUsePictureInPicture: Bool {
        hasCurrentItem && pipState != .unsupported
    }

    private var canSeek: Bool {
        switch playbackState {
        case .ready, .playing, .paused, .buffering, .ended:
            true
        default:
            false
        }
    }

    private var canTogglePlayback: Bool {
        hasCurrentItem && !isLoading
    }

    private var hasCurrentItem: Bool {
        switch playbackState {
        case .ready, .playing, .paused, .buffering, .ended:
            true
        default:
            false
        }
    }

    private var isLoading: Bool {
        if case .loading = playbackState {
            return true
        }
        return false
    }

    private var statusLabel: String {
        switch playbackState {
        case .idle:
            "Idle"
        case .loading:
            "Loading"
        case .ready:
            "Ready"
        case .playing:
            "Playing"
        case .paused:
            "Paused"
        case .buffering:
            "Buffering"
        case .ended:
            "Ended"
        case .failed:
            "Error"
        }
    }

    private var accessibilityPlaybackValue: String {
        "\(statusLabel), \(timeString(currentSeconds)) of \(timeString(durationSeconds))"
    }

    private var playerAspectRatio: Double {
        guard let aspectRatio = presentationInfo?.aspectRatio, aspectRatio.isFinite else {
            return 16 / 9
        }
        return min(max(aspectRatio, 0.56), 2.4)
    }

    private var videoGravity: AVLayerVideoGravity {
        videoZoomScale > 1.01 ? .resizeAspectFill : .resizeAspect
    }

    private var scopedVideoPosterSignature: String {
        scopedVideoItems
            .map { "\($0.id):\($0.artworkURLString ?? ""):\($0.playbackURLString ?? "")" }
            .joined(separator: "|")
    }

    private var formatCapabilityMessage: String {
        guard let capabilities else {
            return "Capabilities appear after a video loads."
        }

        var parts: [String] = []
        if isHDRContent { parts.append("HDR") }
        if capabilities.isHighFrameRate { parts.append("High frame rate") }
        if capabilities.hasAudioVariants { parts.append("Audio variants") }
        if capabilities.hasChapters { parts.append("Chapters") }
        switch capabilities.immersiveMediaProfile {
        case .standard2D:
            parts.append("2D video")
        case .stereo3D:
            parts.append("Stereo 3D")
        case .spatialVideo:
            parts.append("Spatial video")
        case .appleImmersiveVideo:
            parts.append("Apple Immersive Video")
        case .appleProjectedMedia:
            parts.append("Projected media")
        case .unknownImmersive:
            parts.append("Immersive media")
        }
        return parts.joined(separator: ", ")
    }

    private var formatCapabilityStatus: String {
        guard let capabilities else { return "Waiting" }
        if capabilities.immersiveMediaProfile != .standard2D {
            return "Handoff"
        }
        return isHDRContent ? "HDR" : "Standard"
    }

    private var aspectCapabilityMessage: String {
        guard let presentationInfo else {
            return "Aspect analysis appears after a video loads."
        }

        if presentationInfo.isSquare {
            return "Square video detected. The player keeps the original framing instead of forcing 16:9."
        }
        if presentationInfo.isLandscape {
            return "Landscape video detected. The player keeps the source aspect ratio."
        }
        return "Portrait video detected. The player keeps the source aspect ratio."
    }

    private var aspectCapabilityStatus: String {
        guard let presentationInfo else { return "Waiting" }
        if presentationInfo.isSquare { return "Square" }
        return presentationInfo.isLandscape ? "Landscape" : "Portrait"
    }

    private var hdrCapabilityMessage: String {
        return "HDR content is detected and this display reports HDR-capable presentation support."
    }

    private var hdrCapabilityStatus: String {
        "HDR"
    }

    private var showsHDRBadge: Bool {
        HDRDetector().shouldShowHDRBadge(
            isHDRContent: isHDRContent,
            deviceSupportsHDR: deviceSupportsHDRDisplay
        )
    }

    private func configureRemoteControlBridge() {
        remoteControlBridge.currentPositionProvider = { currentSeconds }
        remoteControlBridge.playAction = {
            playbackRuntime?.auraPlayRegisterVideoRemoteControls(remoteControlBridge)
            controller.play()
        }
        remoteControlBridge.pauseAction = {
            controller.pause()
            persistCurrentPosition()
        }
        remoteControlBridge.toggleAction = {
            togglePlayback()
        }
        remoteControlBridge.seekAction = { seconds in
            currentSeconds = min(max(0, seconds), durationSeconds)
            await controller.seek(to: currentSeconds, kind: .skip)
            persistCurrentPosition()
        }
        remoteControlBridge.nextAction = {
            await loadAdjacentVideo(offset: 1)
        }
        remoteControlBridge.previousAction = {
            await loadAdjacentVideo(offset: -1)
        }
        remoteControlBridge.stopAction = {
            persistCurrentPosition()
            await videoIntegrationCoordinator?.stop()
            videoIntegrationCoordinator = nil
            playbackState = .idle
        }
    }

    private func loadVideo(_ item: MusicLibraryItem) async {
        guard let media = playableVideoMedia(for: item) else {
            lastErrorMessage = "This video source could not be resolved."
            statusMessage = "The selected media cannot be loaded."
            playbackState = .failed(.unresolvedURL)
            return
        }

        await loadVideo(media)
    }

    private func loadVideo(id: String) async {
        guard let item = scopedVideoItems.first(where: { $0.sourceNFTID == id }) else {
            return
        }
        await loadVideo(item)
        }

    private func loadVideo(_ media: AuraPlayableMediaItem) async {
        configureRemoteControlBridge()
        await playbackRuntime?.auraPlayPrepareForVideoPlayback(media)
        selectedMedia = media
        playbackState = .loading(media.sourceURL)
        statusMessage = "Loading \(media.metadata.title)."
        lastErrorMessage = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        availableSubtitles = []
        availableAudioTracks = []
        audioDescriptionTracks = []
        chapters = []
        capabilities = nil
        presentationInfo = nil
        isHDRContent = false
        deviceSupportsHDRDisplay = Self.currentDisplaySupportsHDR
        selectedSubtitleID = nil
        selectedAudioTrackID = nil
        selectedAudioDescriptionTrackID = nil
        await videoIntegrationCoordinator?.stop()
        videoIntegrationCoordinator = nil

        do {
            try VideoFormatValidator().validateResolvedPlaybackURL(media.sourceURL)
            let coordinator = makeVideoIntegrationCoordinator(for: media)
            videoIntegrationCoordinator = coordinator
            coordinator.startObserving(observesPlaybackEvents: false)
            _ = try await coordinator.load(media: media)
            resumePosition = resumablePosition(
                from: await playbackRuntime?.auraPlayStoredVideoPosition(for: media.id)
            )
            statusMessage = "\(media.metadata.title) is ready."
            await loadMediaTracks()
        } catch {
            let playbackError = (error as? VideoPlaybackError) ?? .videoLoadFailed(error.localizedDescription)
            lastErrorMessage = userFacingError(playbackError)
            statusMessage = "The selected video could not be loaded."
            playbackState = .failed(playbackError)
            presentVideoToast(for: playbackError)
            if playbackError == .unsupportedVideoFormat {
                await loadAdjacentVideo(offset: 1)
            }
        }
    }

    private func loadMediaTracks() async {
        guard let item = controller.player.currentItem else { return }
        availableSubtitles = (try? await subtitleTrackManager.availableTracks(for: item)) ?? []
        _ = try? await subtitleTrackManager.autoSelectPreferredTrack(on: item)
        availableAudioTracks = (try? await trackManager.availableAudioTracks(for: item)) ?? []
        audioDescriptionTracks = (try? await subtitleTrackManager.availableAudioDescriptionTracks(for: item)) ?? []
        chapters = (try? await trackManager.chapters(for: item.asset)) ?? []
        capabilities = try? await trackManager.capabilities(for: item)
        presentationInfo = try? await VideoPresentationAnalyzer().analyze(asset: item.asset)
        isHDRContent = (try? await HDRDetector().isHDR(asset: item.asset)) ?? false
        updateOrientationLock(for: presentationInfo)
    }

    private func playableVideoMedia(for item: MusicLibraryItem) -> AuraPlayableMediaItem? {
        guard let playbackURLString = item.playbackURLString,
              let sourceURL = urlResolver.resolve(playbackURLString) else {
            return nil
        }

        return AuraPlayableMediaItem(
            id: item.id,
            sourceURL: sourceURL,
            declaredFormat: sourceURL.pathExtension.nilIfEmpty,
            contentKind: .video,
            metadata: MediaMetadata(
                id: item.id,
                title: item.title,
                artist: item.artistName ?? item.collectionName,
                artworkURL: item.artworkURL
            )
        )
    }

    private func makeVideoIntegrationCoordinator(for media: AuraPlayableMediaItem) -> VideoPlaybackIntegrationCoordinator {
        VideoPlaybackIntegrationCoordinator(
            controller: controller,
            metadata: media.metadata,
            playbackStateStore: nil,
            nowPlayingPublisher: VideoNowPlayingPublisherAdapter(publisher: nowPlayingPublisher),
            remoteCommandStream: nil,
            mediaSessionManager: mediaSessionManager,
            gatewayResolver: AuralisVideoGatewayFallbackResolver(),
            pictureInPictureController: pictureInPictureController,
            coordinatedPlaybackConfiguration: VideoCoordinatedPlaybackConfiguration(
                sessionIdentity: sharedSessionIdentity(for: media),
                startsPictureInPictureWhenEnteringBackground: true
            )
        )
    }

    private func sharedSessionIdentity(for media: AuraPlayableMediaItem) -> SharedMediaSessionIdentity {
        SharedMediaSessionIdentity(
            id: SharedMediaSessionID(rawValue: "auraplay.video.\(media.id)"),
            activity: SharedMediaActivityIdentity(
                id: MediaShareActivityID(rawValue: "auraplay.video.\(media.id)"),
                activityIdentifier: SharedMediaActivityIdentifier(rawValue: "com.auralis.auraplay.video"),
                title: media.metadata.title,
                subtitle: media.metadata.artist,
                previewImageID: media.metadata.artworkURL?.absoluteString,
                fallbackURL: media.sourceURL,
                contentKind: .video,
                activityType: .watchTogether
            ),
            queue: SharedMediaQueueIdentity(
                id: SharedMediaQueueID(rawValue: "auraplay.video.walletScope"),
                itemIDs: scopedVideoItems.map(\.id),
                currentItemID: media.id
            )
        )
    }

    private func loadAdjacentVideo(offset: Int) async {
        guard let selectedMedia,
              let currentIndex = scopedVideoItems.firstIndex(where: { $0.id == selectedMedia.id }) else {
            return
        }
        let nextIndex = currentIndex + offset
        guard scopedVideoItems.indices.contains(nextIndex) else { return }
        await loadVideo(scopedVideoItems[nextIndex])
    }

    private func canLoadAdjacentVideo(offset: Int) -> Bool {
        guard let selectedMedia,
              let currentIndex = scopedVideoItems.firstIndex(where: { $0.id == selectedMedia.id }) else {
            return false
        }
        return scopedVideoItems.indices.contains(currentIndex + offset)
    }

    private func togglePlayback() {
        switch playbackState {
        case .playing:
            controller.pause()
            statusMessage = "Playback paused."
            persistCurrentPosition()
        case .ended:
            Task {
                await controller.seek(to: 0, kind: .resume)
                playbackRuntime?.auraPlayRegisterVideoRemoteControls(remoteControlBridge)
                controller.play()
            }
        default:
            playbackRuntime?.auraPlayRegisterVideoRemoteControls(remoteControlBridge)
            controller.play()
            statusMessage = "Playing \(selectedMedia?.metadata.title ?? "video")."
        }
    }

    private func seekEditingChanged(_ editing: Bool) {
        isDragging = editing
        if !editing {
            Task {
                await controller.seek(to: currentSeconds, kind: .scrub)
                persistCurrentPosition()
            }
        }
    }

    private func selectSubtitle(_ track: SubtitleTrack?) async {
        guard let item = controller.player.currentItem else { return }
        try? await subtitleTrackManager.select(track: track, on: item)
        selectedSubtitleID = track?.id
    }

    private func selectAudioTrack(_ track: VideoAudioTrack?) async {
        guard let item = controller.player.currentItem else { return }
        try? await trackManager.select(audioTrack: track, on: item)
        selectedAudioTrackID = track?.id
        selectedAudioDescriptionTrackID = nil
    }

    private func selectAudioDescriptionTrack(_ track: AudioDescriptionTrack?) async {
        guard let item = controller.player.currentItem else { return }
        if let track {
            let audioTrack = VideoAudioTrack(
                id: track.id,
                displayName: track.displayName,
                languageCode: track.languageCode,
                isDefault: false
            )
            try? await trackManager.select(audioTrack: audioTrack, on: item)
            selectedAudioTrackID = nil
            selectedAudioDescriptionTrackID = track.id
        } else {
            try? await trackManager.select(audioTrack: nil, on: item)
            selectedAudioDescriptionTrackID = nil
        }
    }

    private func configurePictureInPicture(_ layer: AVPlayerLayer) {
        if pictureInPictureController == nil {
            let controller = PictureInPictureController(playerLayer: layer)
            controller.onStateChanged = { state in
                Task { @MainActor in
                    pipState = state
                }
            }
            controller.onRestoreRequested = {
                let didRestoreRoute = restoreVideoRoute()
                showFullscreen = didRestoreRoute
                return didRestoreRoute
            }
            pictureInPictureController = controller
            pipState = controller.state
        }
    }

    private func togglePictureInPicture() {
        switch pipState {
        case .active, .starting:
            pictureInPictureController?.stop()
        case .inactive, .stopping:
            pictureInPictureController?.start()
        case .unsupported:
            statusMessage = "Picture in Picture is not available on this device."
        }
    }

    private func observeVideoEvents() async {
        for await event in controller.events {
            await videoIntegrationCoordinator?.handlePlaybackEvent(event)
            switch event {
            case .stateChanged(let state):
                playbackState = state
                statusMessage = userFacingStatus(for: state)
                if case .ready(let duration) = state, let duration {
                    durationSeconds = max(duration, 1)
                }
                if case .failed(let error) = state {
                    lastErrorMessage = userFacingError(error)
                    presentVideoToast(for: error)
                }
            case .tick(let tick):
                if !isDragging {
                    currentSeconds = tick.currentSeconds
                }
                if let duration = tick.durationSeconds {
                    durationSeconds = max(duration, 1)
                }
                if let mediaID = selectedMedia?.id {
                    await playbackRuntime?.auraPlayPersistVideoPositionIfNeeded(
                        mediaID: mediaID,
                        tick: tick,
                        isPlaying: playbackState == .playing
                    )
                }
            case .didPlayToEnd:
                if let mediaID = selectedMedia?.id {
                    await playbackRuntime?.auraPlayMarkVideoCompleted(mediaID: mediaID)
                }
                playbackState = .ended
                statusMessage = "Playback ended."
            case .failedToPlayToEnd(let message):
                lastErrorMessage = message ?? "Playback stopped before the end."
                statusMessage = "Playback stopped before the end."
            case .playbackStalled:
                playbackState = .buffering
                statusMessage = "Playback is buffering. Checking another gateway if this keeps stalling."
            case .externalPlaybackChanged(let active):
                isExternalPlaybackActive = active
                statusMessage = active ? "AirPlay is active." : "Local playback is active."
            case .waitingReasonChanged(let reason):
                if let reason {
                    statusMessage = userFacingWaitingReason(reason)
                }
            }
        }
    }

    private func persistCurrentPosition() {
        guard let selectedMedia else { return }
        guard playbackState != .ended else { return }
        let tick = PlaybackTick(
            currentSeconds: currentSeconds,
            durationSeconds: durationSeconds
        )
        Task {
            await playbackRuntime?.auraPlayPersistVideoPositionIfNeeded(
                mediaID: selectedMedia.id,
                tick: tick,
                isPlaying: playbackState == .playing,
                force: true
            )
        }
    }

    private func handleDoubleTapSeek(at location: CGPoint, in size: CGSize) {
        guard canSeek else { return }
        let isForward = location.x >= size.width / 2
        let target = isForward
            ? min(durationSeconds, currentSeconds + 15)
            : max(0, currentSeconds - 15)
        currentSeconds = target
        statusMessage = isForward ? "Skipped forward 15 seconds." : "Skipped backward 15 seconds."
        Task {
            await controller.seek(to: target, kind: .skip)
        }
    }

    private func resumablePosition(from position: StoredVideoPlaybackPosition?) -> StoredVideoPlaybackPosition? {
        guard let position else { return nil }
        guard position.positionMilliseconds > 5_000 else { return nil }
        if let durationMilliseconds = position.durationMilliseconds,
           durationMilliseconds - position.positionMilliseconds <= 5_000 {
            return nil
        }
        return position
    }

    private func presentVideoToast(for error: VideoPlaybackError) {
        switch error {
        case .unsupportedVideoFormat:
            videoToast = VideoPlaybackToast(
                title: "Unsupported Video",
                message: "AuraPlay skipped a video format this device cannot play."
            )
        case .videoLoadFailed:
            videoToast = VideoPlaybackToast(
                title: "Video Load Failed",
                message: userFacingError(error)
            )
        default:
            break
        }
    }

    private func scheduleGatewayFallbackIfNeeded() {
        guard fallbackTask == nil, let selectedMedia else { return }
        let stalledAt = currentSeconds
        let originalURL = selectedMedia.sourceURL

        fallbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, playbackState == .buffering, currentSeconds <= stalledAt + 0.5 else {
                fallbackTask = nil
                return
            }

            guard VideoBufferingPolicy().isGatewayURL(originalURL),
                  let fallbackURL = try? await AuralisVideoGatewayFallbackResolver().nextResolvedURL(after: originalURL) else {
                fallbackTask = nil
                return
            }

            do {
                statusMessage = "Still buffering. Retrying through another gateway."
                try await controller.load(resolvedURL: fallbackURL)
                await controller.seek(to: stalledAt, kind: .resume)
                controller.play()
                statusMessage = "Recovered playback through another gateway."
            } catch {
                let playbackError = (error as? VideoPlaybackError) ?? .videoLoadFailed(error.localizedDescription)
                lastErrorMessage = userFacingError(playbackError)
                playbackState = .failed(playbackError)
                presentVideoToast(for: playbackError)
            }
            fallbackTask = nil
        }
    }

    private func generateMissingPosterFrames() async {
        let generator = CachedPosterFrameGenerator(cache: posterCache)
        for item in scopedVideoItems where item.artworkURL == nil && posterImages[item.id] == nil {
            guard let playbackURLString = item.playbackURLString,
                  let sourceURL = urlResolver.resolve(playbackURLString) else {
                continue
            }

            let asset = AVURLAsset(url: sourceURL)
            guard let poster = await generator.poster(for: asset, mediaID: item.id, maximumWidth: 240) else {
                continue
            }
            posterImages[item.id] = poster
        }
    }

    private func updateOrientationLock(for info: VideoPresentationInfo?) {
        #if canImport(UIKit)
        AuraVideoOrientationLock.shared.update(for: info)
        #endif
    }

    private func userFacingStatus(for state: VideoPlaybackState) -> String {
        switch state {
        case .idle:
            "Select a video from the current wallet scope."
        case .loading:
            "Loading video."
        case .ready:
            "Video is ready."
        case .playing:
            "Playing video."
        case .paused:
            "Playback paused."
        case .buffering:
            "Playback is buffering."
        case .ended:
            "Playback ended."
        case .failed(let error):
            userFacingError(error)
        }
    }

    private func userFacingError(_ error: VideoPlaybackError) -> String {
        switch error {
        case .unresolvedURL:
            "The video source could not be resolved."
        case .unsupportedVideoFormat:
            "This video format is not supported."
        case .videoLoadFailed(let message):
            message ?? "The video could not be loaded."
        case .pictureInPictureUnsupported:
            "Picture in Picture is not available for this video."
        case .noCurrentItem:
            "Load a video before changing playback options."
        case .resourceLoadingUnsupported:
            "This video resource cannot be loaded by the current player."
        case .controllerTornDown:
            "This video player has already been closed. Open the video again to restart playback."
        }
    }

    private func userFacingWaitingReason(_ reason: VideoWaitingReason) -> String {
        switch reason {
        case .evaluatingBufferingRate, .minimizingStalls:
            "Playback is buffering. It will resume automatically."
        case .noItemToPlay:
            "Load a video before starting playback."
        case .unknown:
            "Playback is waiting for media."
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = max(Int(seconds.rounded()), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private static var currentDisplaySupportsHDR: Bool {
        #if canImport(UIKit)
        guard let screen = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.screen })
            .first else {
            return false
        }
        if #available(iOS 16.0, tvOS 16.0, *) {
            return screen.potentialEDRHeadroom > 1
        }
        return false
        #else
        false
        #endif
    }
}

private struct VideoLibraryPresentationItem: Identifiable {
    var id: String { itemID }

    let itemID: String
    let mediaID: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let posterImage: PlatformImage?

    init(item: MusicLibraryItem, posterImage: PlatformImage?) {
        itemID = item.id
        mediaID = item.sourceNFTID
        title = item.title
        subtitle = item.artistName ?? item.collectionName ?? item.contentType ?? "Video"
        artworkURL = item.artworkURL
        self.posterImage = posterImage
    }
}

private struct VideoLibraryRow: View {
    let item: VideoLibraryPresentationItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            .frame(width: 52, height: 52)
            .clipShape(.rect(cornerRadius: 10))
            .mediaAccessibility(.decorative)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Selected")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let artworkURL = item.artworkURL {
            AsyncImage(url: artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
        } else if let posterImage = item.posterImage {
            #if canImport(UIKit)
            Image(uiImage: posterImage)
                .resizable()
                .scaledToFill()
            #elseif canImport(AppKit)
            Image(nsImage: posterImage)
                .resizable()
                .scaledToFill()
            #else
            placeholder
            #endif
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondary.opacity(0.16))
            .overlay {
                Image(systemName: "play.rectangle")
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }
    }
}

private struct VideoLibraryList: View {
    let rows: [VideoLibraryPresentationItem]
    let selectedID: String?
    let load: (String) -> Void

    var body: some View {
        if rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("No Videos Indexed", systemImage: "play.rectangle")
                    .font(.subheadline.weight(.semibold))
                Text("Video-capable NFT media for the active wallet will appear here after library sync.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            ForEach(rows, id: \VideoLibraryPresentationItem.itemID) { item in
                rowButton(for: item)
            }
        }
    }

    private func rowButton(for item: VideoLibraryPresentationItem) -> some View {
        let accessibilityID = A11yID.AuraPlay.videoItem(id: item.mediaID)

        return Button {
            load(item.mediaID)
        } label: {
            VideoLibraryRow(item: item, isSelected: selectedID == item.itemID)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct VideoOverlayStatus: View {
    let title: String
    let message: String
    let systemImage: String
    var showsProgress = false

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: systemImage)
                    .font(.title)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.58))
        .accessibilityElement(children: .combine)
    }
}

private struct VideoCapabilityRow: View {
    let title: String
    let message: String
    let systemImage: String
    let status: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

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

private struct VideoPlaybackToast: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

private struct VideoPlaybackToastView: View {
    let toast: VideoPlaybackToast

    var body: some View {
        LiquidGlassOverlayContainer {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(toast.title)
                        .font(.subheadline.weight(.semibold))
                    Text(toast.message)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(toast.title). \(toast.message)")
    }
}

private struct LiquidGlassOverlayContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private actor InMemoryVideoArtworkCache: VideoArtworkCaching {
    private var posters: [String: PlatformImage] = [:]

    func cachedPoster(for mediaID: String) async -> PlatformImage? {
        posters[mediaID]
    }

    func storePoster(_ image: PlatformImage, for mediaID: String) async {
        posters[mediaID] = image
    }
}

private final class VideoNowPlayingPublisherAdapter: VideoNowPlayingPublishing, @unchecked Sendable {
    private let publisher: NowPlayingPublisher

    init(publisher: NowPlayingPublisher) {
        self.publisher = publisher
    }

    func publish(metadata: MediaMetadata, tick: PlaybackTick, isPlaying: Bool) async {
        await publisher.update(NowPlayingState(
            title: metadata.title,
            artist: metadata.artist,
            duration: tick.durationSeconds,
            elapsedTime: tick.currentSeconds,
            playbackRate: isPlaying ? 1 : 0,
            mediaType: .video
        ))
    }

    func clear(metadataID: String) async {
        await publisher.clear()
    }
}

@MainActor
private final class AuraPlayVideoRemoteControlBridge: AuraPlayVideoRemoteControlling {
    var currentPositionProvider: () -> TimeInterval = { 0 }
    var playAction: () -> Void = {}
    var pauseAction: () -> Void = {}
    var toggleAction: () -> Void = {}
    var seekAction: (TimeInterval) async -> Void = { _ in }
    var nextAction: () async -> Void = {}
    var previousAction: () async -> Void = {}
    var stopAction: () async -> Void = {}

    var currentPosition: TimeInterval {
        currentPositionProvider()
    }

    func play() {
        playAction()
    }

    func pause() {
        pauseAction()
    }

    func togglePlayPause() {
        toggleAction()
    }

    func seek(to seconds: TimeInterval) async {
        await seekAction(seconds)
    }

    func skipToNext() async {
        await nextAction()
    }

    func skipToPrevious() async {
        await previousAction()
    }

    func stopForAudioHandoff() async {
        await stopAction()
    }
}

private struct AuralisVideoGatewayFallbackResolver: VideoGatewayResolving {
    private let ipfsGatewayHosts = [
        "ipfs.io",
        "cloudflare-ipfs.com",
        "gateway.pinata.cloud"
    ]

    func nextResolvedURL(after failedURL: URL) async throws -> URL? {
        guard let host = failedURL.host?.lowercased(),
              ipfsGatewayHosts.contains(host),
              let cidPath = ipfsCIDPath(from: failedURL) else {
            return nil
        }

        let candidates = ipfsGatewayHosts.compactMap { gatewayHost -> URL? in
            guard gatewayHost != host else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = gatewayHost
            components.path = "/ipfs/" + cidPath
            return components.url
        }
        return candidates.first
    }

    private func ipfsCIDPath(from url: URL) -> String? {
        let components = url.path
            .split(separator: "/")
            .map(String.init)
        guard let ipfsIndex = components.firstIndex(of: "ipfs") else {
            return components.isEmpty ? nil : components.joined(separator: "/")
        }
        let cidComponents = components.dropFirst(ipfsIndex + 1)
        guard !cidComponents.isEmpty else { return nil }
        return cidComponents.joined(separator: "/")
    }
}


private extension MusicLibraryItem {
    var isPlaybackReady: Bool {
        availability == .ready && playbackURLString?.isEmpty == false
    }

    var isVideoCapable: Bool {
        if let contentType = contentType?.lowercased(), contentType.hasPrefix("video/") {
            return true
        }
        guard let playbackURLString,
              let url = URL(string: playbackURLString.lowercased()) else {
            return false
        }
        return ["mp4", "m4v", "mov", "m3u8"].contains(url.pathExtension)
    }

    var artworkURL: URL? {
        guard let artworkURLString else { return nil }
        return URL(string: artworkURLString)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
