import AuraPlayMediaCore
import AuraUI
import SwiftUI

public struct AuraPlayPlayerView<Commander: AuraPlayPlayerCommanding, VideoSurface: View>: View {
    public let presentation: AuraPlayPlayerPresentation
    public let commander: Commander
    public let videoSurface: VideoSurface
    public let videoRoutePicker: AnyView?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsUpNext = false
    @State private var showsAudioControls = false
    @State private var isVideoChromeVisible = true
    @State private var showsCopyToast = false
    @State private var provenancePresentation: AuraPlayProvenancePresentation?
    /// One coalescer serves the scrubber and both gesture layers (P10-002).
    @State private var seekCoalescer = SeekCoalescer()

    public init(
        presentation: AuraPlayPlayerPresentation,
        commander: Commander,
        videoRoutePicker: AnyView? = nil,
        @ViewBuilder videoSurface: () -> VideoSurface
    ) {
        self.presentation = presentation
        self.commander = commander
        self.videoRoutePicker = videoRoutePicker
        self.videoSurface = videoSurface()
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if let item = presentation.item {
                        if item.mediaKind == .video {
                            videoLayout(item)
                        } else {
                            audioLayout(item)
                        }
                    } else {
                        AuraEmptyState(
                            title: "Nothing Playing",
                            message: "Choose media from your library to start AuraPlay.",
                            systemImage: "music.note"
                        )
                        .padding(24)
                    }
                }

                if showsCopyToast {
                    copyToast
                }
            }
            .navigationTitle("Now Playing")
            .auraPlayInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Dismiss player")
                    .accessibilityIdentifier(A11yID.AuraPlay.playerDismiss)
                }
            }
            .background(playerBackground)
        }
        .environment(\.colorScheme, .dark)
        .tint(.white)
        .accessibilityIdentifier(A11yID.AuraPlay.playerSheet)
        .sheet(isPresented: $showsUpNext) {
            AuraPlayUpNextSheet(queue: presentation.queue, commander: commander)
        }
        .sheet(isPresented: $showsAudioControls) {
            if let audioCapabilities = presentation.audioCapabilities {
                AuraPlayAudioControlsSheet(capabilities: audioCapabilities, commander: commander)
            }
        }
        .sheet(item: $provenancePresentation) { presentation in
            ProvenancePanelView(presentation: presentation) { _ in
                Task {
                    await commander.copyContractAddress()
                    presentCopyToast()
                }
            }
        }
        .task(id: isVideoChromeVisible) {
            guard presentation.item?.mediaKind == .video, isVideoChromeVisible else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.2)) {
                isVideoChromeVisible = false
            }
        }
    }

    // MARK: - Layouts

    private func audioLayout(_ item: AuraPlayPlayerItemPresentation) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                audioMediaBranch(item)
                titleBlock(item)
                AuraPlayPlayerScrubberView(
                    position: presentation.position,
                    commander: commander,
                    seekCoalescer: seekCoalescer
                )
                transportControls
                secondaryControls(item)
                failureMessage
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    /// Video is full-bleed: the surface spans the full width above the
    /// scrolling controls instead of sitting in a rounded inset card.
    private func videoLayout(_ item: AuraPlayPlayerItemPresentation) -> some View {
        VStack(spacing: 0) {
            videoMediaBranch(item)
                .frame(maxWidth: .infinity)

            ScrollView {
                VStack(spacing: 20) {
                    titleBlock(item)
                    AuraPlayPlayerScrubberView(
                        position: presentation.position,
                        commander: commander,
                        seekCoalescer: seekCoalescer
                    )
                    transportControls
                    secondaryControls(item)
                    failureMessage
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Ambient background

    /// Blurred artwork provides the dominant-color ambient treatment for
    /// audio; Reduce Transparency and video fall back to an opaque surface.
    @ViewBuilder
    private var playerBackground: some View {
        if !reduceTransparency,
           let item = presentation.item,
           item.mediaKind == .audio,
           let artworkURLString = item.artworkURLString,
           let url = URL(string: artworkURLString) {
            ZStack {
                CachedAsyncImage(url: url, mediaAccessibility: .decorative)
                    .scaledToFill()
                    .blur(radius: 60, opaque: true)
                    .overlay(.black.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()
        } else {
            Color.background
                .ignoresSafeArea()
        }
    }

    // MARK: - Media branches

    private func audioMediaBranch(_ item: AuraPlayPlayerItemPresentation) -> some View {
        ZStack {
            artwork(item)
            AuraPlayPlayerGestureLayer(
                mediaKind: item.mediaKind,
                currentSeconds: presentation.position.currentSeconds,
                durationSeconds: presentation.position.durationSeconds,
                commander: commander,
                accessibilityIdentifier: A11yID.AuraPlay.playerArtwork,
                isVideoChromeVisible: $isVideoChromeVisible,
                seekCoalescer: seekCoalescer,
                dismiss: { dismiss() }
            )
        }
    }

    private func videoMediaBranch(_ item: AuraPlayPlayerItemPresentation) -> some View {
        ZStack(alignment: .bottom) {
            videoSurface
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .accessibilityLabel("Video playback surface")
                .accessibilityIdentifier(A11yID.AuraPlay.playerVideoSurface)

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            AuraPlayPlayerGestureLayer(
                mediaKind: item.mediaKind,
                currentSeconds: presentation.position.currentSeconds,
                durationSeconds: presentation.position.durationSeconds,
                commander: commander,
                accessibilityIdentifier: A11yID.AuraPlay.playerVideoSurface,
                isVideoChromeVisible: $isVideoChromeVisible,
                seekCoalescer: seekCoalescer,
                dismiss: { dismiss() }
            )

            if let videoCapabilities = presentation.videoCapabilities, isVideoChromeVisible {
                AuraPlayVideoControlsOverlay(
                    capabilities: videoCapabilities,
                    commander: commander,
                    routePicker: videoRoutePicker
                )
                .padding(12)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func artwork(_ item: AuraPlayPlayerItemPresentation) -> some View {
        if let artworkURLString = item.artworkURLString,
           let url = URL(string: artworkURLString) {
            CachedAsyncImage(url: url, mediaAccessibility: .meaningful("\(item.title) artwork"))
                .scaledToFill()
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 240 : 320)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 22))
                .accessibilityIdentifier(A11yID.AuraPlay.playerArtwork)
        } else {
            RoundedRectangle(cornerRadius: 22)
                .fill(.secondary.opacity(0.18))
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 240 : 320)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: item.mediaKind == .video ? "play.rectangle" : "music.note")
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
        }
    }

    private func titleBlock(_ item: AuraPlayPlayerItemPresentation) -> some View {
        VStack(spacing: 6) {
            // Marquee only when Reduce Motion is off; truncation otherwise (P10-001).
            if reduceMotion {
                Text(item.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
            } else {
                AuraPlayMarqueeText(text: item.title, font: .title2.weight(.bold))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
            }
            if let creator = item.creator, !creator.isEmpty {
                Text(creator)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }
            if let collection = item.collection, !collection.isEmpty {
                Text(collection)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.54))
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var transportControls: some View {
        HStack(spacing: 24) {
            Button {
                Task { await commander.skipPrevious() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Previous track")
            .accessibilityIdentifier(A11yID.AuraPlay.playerPrevious)

            Button {
                Task { await commander.togglePlayPause() }
            } label: {
                Image(systemName: playPauseSystemImage)
                    .font(.system(size: 46))
            }
            .frame(minWidth: 56, minHeight: 56)
            .accessibilityLabel(playPauseLabel)
            .accessibilityIdentifier(A11yID.AuraPlay.playerPlayPause)

            Button {
                Task { await commander.skipNext() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Next track")
            .accessibilityIdentifier(A11yID.AuraPlay.playerNext)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func secondaryControls(_ item: AuraPlayPlayerItemPresentation) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                secondaryButtons(item)
            }
            VStack(spacing: 10) {
                secondaryButtons(item)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func secondaryButtons(_ item: AuraPlayPlayerItemPresentation) -> some View {
        Button("Up Next", systemImage: "music.note.list") {
            showsUpNext = true
        }
        .accessibilityIdentifier(A11yID.AuraPlay.playerUpNext)

        Button("Shuffle", systemImage: presentation.queue.isShuffleEnabled ? "shuffle.circle.fill" : "shuffle") {
            Task { await commander.setShuffleEnabled(!presentation.queue.isShuffleEnabled) }
        }
        .accessibilityValue(presentation.queue.isShuffleEnabled ? "On" : "Off")
        .accessibilityIdentifier(A11yID.AuraPlay.playerShuffle)

        Button("Repeat: \(presentation.queue.repeatModeTitle)", systemImage: "repeat") {
            Task { await commander.cycleRepeatMode() }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.playerRepeat)

        if item.mediaKind == .audio, presentation.audioCapabilities != nil {
            Button("Audio", systemImage: "slider.horizontal.3") {
                showsAudioControls = true
            }
            .accessibilityIdentifier(A11yID.AuraPlay.playerAudioControls)
        }

        Button("Share", systemImage: "square.and.arrow.up") {
            Task { await commander.shareCurrentItem() }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.playerShare)

        if item.contractAddress?.isEmpty == false || item.tokenID?.isEmpty == false {
            Menu {
                AuraPlayPlayerContextMenuBuilder.playerMenu(
                    item: item,
                    commander: commander,
                    showProvenance: {
                        provenancePresentation = AuraPlayProvenancePresentation(
                            title: item.title,
                            chainName: item.chainDisplayName ?? "Unknown Chain",
                            contractAddress: item.contractAddress,
                            tokenID: item.tokenID,
                            tokenType: nil,
                            collectionName: item.collection,
                            explorerURL: item.explorerURL
                        )
                    },
                    onCopied: { presentCopyToast() }
                )
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Copy toast (P10-007)

    private var copyToast: some View {
        Label("Contract address copied", systemImage: "doc.on.doc.fill")
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .padding(.bottom, 28)
            .transition(.opacity)
            .accessibilityIdentifier(A11yID.AuraPlay.playerCopyToast)
    }

    private func presentCopyToast() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .easeInOut(duration: 0.2)) {
            showsCopyToast = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                showsCopyToast = false
            }
        }
    }

    @ViewBuilder
    private var failureMessage: some View {
        if let failureMessage = presentation.failureMessage, presentation.playbackState == .failed {
            Label(failureMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var playPauseSystemImage: String {
        switch presentation.playbackState {
        case .playing, .buffering:
            "pause.fill"
        default:
            "play.fill"
        }
    }

    private var playPauseLabel: String {
        switch presentation.playbackState {
        case .playing, .buffering:
            "Pause"
        case .loading:
            "Loading playback"
        default:
            "Play"
        }
    }
}

public extension AuraPlayPlayerView where VideoSurface == Color {
    init(presentation: AuraPlayPlayerPresentation, commander: Commander) {
        self.init(presentation: presentation, commander: commander) {
            Color.black
        }
    }
}

/// Scrolls overflowing titles horizontally; callers gate on Reduce Motion.
struct AuraPlayMarqueeText: View {
    let text: String
    let font: Font

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isAnimating = false

    private var overflows: Bool {
        textWidth > containerWidth + 1
    }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(overflows ? 0 : 1)
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { containerWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newValue in
                            containerWidth = newValue
                        }
                }
            }
            .background {
                // Hidden fixed-size copy measures the intrinsic text width.
                Text(text)
                    .font(font)
                    .fixedSize()
                    .hidden()
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { textWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, newValue in
                                    textWidth = newValue
                                }
                        }
                    }
            }
            .overlay(alignment: .leading) {
                if overflows {
                    Text(text)
                        .font(font)
                        .fixedSize()
                        .offset(x: isAnimating ? containerWidth - textWidth : 0)
                        .animation(
                            .linear(duration: max(3, Double(textWidth) / 40)).repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                        .onAppear { isAnimating = true }
                        .onDisappear { isAnimating = false }
                }
            }
            .clipped()
            .accessibilityLabel(text)
    }
}
