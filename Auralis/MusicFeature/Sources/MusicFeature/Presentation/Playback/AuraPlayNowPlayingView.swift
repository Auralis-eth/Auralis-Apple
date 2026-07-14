import AuraUI
import SwiftUI

#if canImport(AVKit) && canImport(UIKit)
import AVKit
import UIKit
#endif

struct AuraPlayNowPlayingView<Player: AuraPlayPlaybackPresenting>: View {
    let player: Player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var seekValue: Double = 0
    @State private var isDraggingSeek = false
    @State private var showQueue = false
    @ScaledMetric(relativeTo: .title) private var primaryPlaybackIconSize = 56
    @ScaledMetric(relativeTo: .title) private var artworkMaxSize = 280

    private var nextPreviewTrack: AuraPlayTrack? { player.auraPlayNextPreviewTrack }
    private var previousPreviewTrack: AuraPlayTrack? { player.auraPlayPreviousPreviewTrack }
    private let previousRestartThreshold: TimeInterval = 3.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Capsule()
                        .frame(width: 40, height: 6)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .accessibilityHidden(true)

                    if let track = player.auraPlayCurrentTrack {
                        VStack(spacing: 24) {
                            VStack(spacing: 16) {
                                artworkView

                                VStack(spacing: 8) {
                                    if let title = track.title, !title.isEmpty {
                                        Text(title)
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                            .accessibilityAddTraits(.isHeader)
                                    }

                                    if let artist = track.artist, !artist.isEmpty {
                                        Text(artist)
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }

                            VStack(spacing: 20) {
                                VStack(spacing: 8) {
                                    Slider(
                                        value: $seekValue,
                                        in: 0...max(1, track.duration),
                                        onEditingChanged: { dragging in
                                            isDraggingSeek = dragging
                                            if !dragging {
                                                try? player.auraPlaySeek(to: seekValue)
                                            }
                                        }
                                    )
                                    .accessibilityLabel(String(localized: "Playback position"))
                                    .accessibilityValue(
                                        String(localized: "\(timeString(from: seekValue)) of \(timeString(from: track.duration))")
                                    )
                                    .accessibilityHint(String(localized: "Swipe up or down to seek"))
                                    .onChange(of: player.auraPlayCurrentTrack) { _, _ in
                                        seekValue = 0
                                    }
                                    .onChange(of: player.auraPlayProgress) { _, newValue in
                                        if !isDraggingSeek {
                                            seekValue = newValue
                                        }
                                    }
                                    .onAppear {
                                        seekValue = player.auraPlayProgress
                                    }

                                    HStack {
                                        Text(timeString(from: seekValue))
                                        Spacer()
                                        Text(timeString(from: track.duration))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 28) {
                                    Button {
                                        player.auraPlaySkipBackward()
                                    } label: {
                                        Image(systemName: "gobackward.15")
                                            .font(.title3)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(String(localized: "Skip backward 15 seconds"))
                                    .accessibilityHint(String(localized: "Moves playback backward by fifteen seconds"))

                                    Button {
                                        Task { await player.auraPlayPrevious() }
                                    } label: {
                                        Image(systemName: "backward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(String(localized: "Previous track"))
                                    .accessibilityHint(String(localized: "Plays the previous track"))

                                    mainPlaybackButton

                                    Button {
                                        Task { await player.auraPlayNext() }
                                    } label: {
                                        Image(systemName: "forward.fill")
                                            .font(.title2)
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(String(localized: "Next track"))
                                    .accessibilityHint(String(localized: "Plays the next track"))

                                    Button {
                                        player.auraPlaySkipForward()
                                    } label: {
                                        Image(systemName: "goforward.15")
                                            .font(.title3)
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityLabel(String(localized: "Skip forward 15 seconds"))
                                    .accessibilityHint(String(localized: "Moves playback forward by fifteen seconds"))
                                }
                            }

                            VStack(spacing: 8) {
                                if let prev = previousPreviewTrack {
                                    previewRow(
                                        title: prev.title ?? "Unknown Track",
                                        artist: prev.artist,
                                        imageURLString: prev.imageURLString,
                                        label: "Previous",
                                        accessibilityPrefix: "Previous",
                                        action: {
                                            if player.auraPlayProgress > previousRestartThreshold {
                                                try? player.auraPlaySeek(to: 0)
                                            } else {
                                                Task { await player.auraPlayPrevious() }
                                            }
                                        }
                                    )
                                }

                                if let next = nextPreviewTrack {
                                    previewRow(
                                        title: next.title ?? "Unknown Track",
                                        artist: next.artist,
                                        imageURLString: next.imageURLString,
                                        label: "Next",
                                        accessibilityPrefix: "Next",
                                        action: {
                                            Task { await player.auraPlayNext() }
                                        }
                                    )
                                }
                            }

                            AuraPlayAudioIntegrationPanel(player: player)

                            AuraPlayRecentlyPlayedSection(player: player)
                            Button("Open Queue", systemImage: "music.note.list") {
                                showQueue = true
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(A11yID.AuraPlay.queue)

                            Color.clear.frame(height: 20)
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note")
                                .font(.system(size: 64))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("No track loaded")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .padding(.top, 100)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Now Playing")
            .auraPlayInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "music.note.list")
                    }
                    .accessibilityLabel("Queue") // [VERIFY] opens the playback queue.
                    .accessibilityHint("Opens the current AuraPlay queue")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .auraSurfaceBackground(style: .soft, cornerRadius: 0)
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showQueue) {
            AuraPlayQueueSheet(player: player)
        }
    }

    @ViewBuilder
    private var mainPlaybackButton: some View {
        switch player.auraPlayPlaybackState {
        case .loading:
            Button(action: player.auraPlayPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: primaryPlaybackIconSize))
            }
            .disabled(true)
            .frame(minWidth: 44, minHeight: 44)
            .overlay {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)
            }
            .accessibilityLabel(String(localized: "Loading playback"))
            .accessibilityHint(String(localized: "Playback is loading"))
            .accessibilityShowsLargeContentViewer()

        case .playing:
            Button(action: player.auraPlayPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: primaryPlaybackIconSize))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "Pause"))
            .accessibilityHint(String(localized: "Pauses the current track"))
            .accessibilityShowsLargeContentViewer()

        case .paused:
            Button {
                try? player.auraPlayResume()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: primaryPlaybackIconSize))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "Resume"))
            .accessibilityHint(String(localized: "Resumes the current track"))
            .accessibilityShowsLargeContentViewer()

        case .stopped:
            Button {
                try? player.auraPlayPlay()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: primaryPlaybackIconSize))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(String(localized: "Play"))
            .accessibilityHint(String(localized: "Starts playback"))
            .accessibilityShowsLargeContentViewer()

        case .error:
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Button("Retry", systemImage: "arrow.clockwise") {
                    try? player.auraPlayPlay()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(String(localized: "Retries playback for the current track or queue"))
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let imageURLString = player.auraPlayCurrentTrack?.imageURLString,
           !imageURLString.isEmpty,
            let imageURL = URL(string: imageURLString) {
            CachedAsyncImage(
                url: imageURL,
                mediaAccessibility: .meaningful(currentArtworkAccessibilityLabel)
            )
                .frame(maxWidth: min(artworkMaxSize, 320), maxHeight: min(artworkMaxSize, 320))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.25))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: min(artworkMaxSize, 320), maxHeight: min(artworkMaxSize, 320))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                .accessibilityHidden(true)
        }
    }

    private func timeString(from seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secondsComponent = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secondsComponent)
    }

    @ViewBuilder
    private func previewRow(
        title: String,
        artist: String?,
        imageURLString: String?,
        label: String,
        accessibilityPrefix: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let urlString = imageURLString,
                   !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    CachedAsyncImage(url: url, mediaAccessibility: .decorative)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "music.note")
                                .foregroundStyle(.gray)
                                .accessibilityHidden(true)
                        }
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                    if let artist, !artist.isEmpty {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(
            String(
                localized: "\(accessibilityPrefix): \(title.isEmpty ? "Unknown Track" : title)\(artist.map { ", by \($0)" } ?? "")"
            )
        )
        .opacity(player.auraPlayPlaybackState == .loading ? 0.85 : 1.0)
    }

    private var currentArtworkAccessibilityLabel: String {
        guard let track = player.auraPlayCurrentTrack else {
            return String(localized: "Track artwork")
        }

        let title = track.title ?? String(localized: "Unknown Track")
        if let artist = track.artist, !artist.isEmpty {
            return String(localized: "\(title) artwork by \(artist)")
        }
        return String(localized: "\(title) artwork")
    }
}

private struct AuraPlayAudioIntegrationPanel<Player: AuraPlayPlaybackPresenting>: View {
    let player: Player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Playback Integration", systemImage: "slider.horizontal.3")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AirPlay", systemImage: "airplayaudio")
                    Spacer()
                    AuraPlayAudioRoutePicker()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("AirPlay") // [VERIFY] opens system route picker.
                }
                .accessibilityElement(children: .contain)

                AuraPlayCapabilityStatusRow(
                    title: "Route mode",
                    message: "The custom audio engine is active for this track. AirPlay routing is available through the system picker.",
                    systemImage: "checkmark.circle",
                    status: player.auraPlaySystemIntegrationPresentation.routeMode
                )

                AuraPlayCapabilityStatusRow(
                    title: "Now Playing",
                    message: "Lock Screen and Control Center metadata are published only for the active long-form track.",
                    systemImage: "rectangle.stack.badge.play",
                    status: player.auraPlaySystemIntegrationPresentation.nowPlayingStatus
                )

                AuraPlayCapabilityStatusRow(
                    title: "Remote commands",
                    message: "System play, pause, seek, previous, next, and 15-second skip commands control the active transport.",
                    systemImage: "dot.radiowaves.left.and.right",
                    status: player.auraPlaySystemIntegrationPresentation.remoteCommandStatus
                )

                AuraPlayCapabilityStatusRow(
                    title: "Spatial Audio",
                    message: "Spatial playback remains owned by the system route. AuraPlay does not imply custom-engine spatial rendering.",
                    systemImage: "airpodspro",
                    status: player.auraPlaySystemIntegrationPresentation.spatialAudioStatus
                )
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier(A11yID.AuraPlay.routeControls)

            VStack(alignment: .leading, spacing: 10) {
                Label("Cache and Offline", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: player.auraPlayCachePresentation.progressFraction ?? 0)
                    .opacity(player.auraPlayCachePresentation.progressFraction == nil ? 0 : 1)
                    .accessibilityLabel("Offline progress")
                    .accessibilityValue(player.auraPlayCachePresentation.accessibilityValue)

                AuraPlayCapabilityStatusRow(
                    title: player.auraPlayCachePresentation.title,
                    message: player.auraPlayCachePresentation.message,
                    systemImage: "externaldrive",
                    status: player.auraPlayCachePresentation.statusLabel
                )
                .accessibilityIdentifier(
                    player.auraPlayCachePresentation.state == .error
                        ? A11yID.AuraPlay.cacheError
                        : A11yID.AuraPlay.cacheStatus
                )

                ViewThatFits(in: .horizontal) {
                    HStack {
                        offlineButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        offlineButtons
                    }
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier(A11yID.AuraPlay.cacheControls)

            AuraPlayAudioTuningPanel(player: player)
                .accessibilityIdentifier(A11yID.AuraPlay.audioTuning)

            AuraPlayLiveVisualizerView(
                presentation: player.auraPlayVisualizationPresentation,
                reduceMotion: reduceMotion
            )
            .accessibilityIdentifier(A11yID.AuraPlay.visualizer)
            .task(id: visualizationTaskID) {
                if shouldPauseVisualization {
                    await player.auraPlayStopVisualization()
                } else {
                    await player.auraPlayStartVisualization()
                }
            }
            .onDisappear {
                Task { await player.auraPlayStopVisualization() }
            }
        }
    }

    private var visualizationTaskID: String {
        [
            reduceMotion ? "reduce-motion" : "motion",
            String(describing: player.auraPlayPlaybackState),
            player.auraPlayCurrentTrack?.id ?? "no-track"
        ].joined(separator: "|")
    }

    private var shouldPauseVisualization: Bool {
        reduceMotion || player.auraPlayPlaybackState != .playing
    }

    @ViewBuilder
    private var offlineButtons: some View {
        Button("Save Offline", systemImage: "arrow.down.circle") {
            Task { await player.auraPlaySaveOffline() }
        }
        .disabled(!player.auraPlayCachePresentation.canSaveOffline)
        .accessibilityIdentifier(A11yID.AuraPlay.cacheSaveOffline)

        Button("Pin", systemImage: "pin") {
            Task { await player.auraPlayPinOffline() }
        }
        .disabled(!player.auraPlayCachePresentation.canPin)
        .accessibilityIdentifier(A11yID.AuraPlay.cachePin)

        Button("Unpin", systemImage: "pin.slash") {
            Task { await player.auraPlayUnpinOffline() }
        }
        .disabled(!player.auraPlayCachePresentation.canUnpin)
        .accessibilityIdentifier(A11yID.AuraPlay.cacheUnpin)
    }
}

private struct AuraPlayAudioTuningPanel<Player: AuraPlayPlaybackPresenting>: View {
    let player: Player

    private var presentation: AuraPlayAudioTuningPresentation {
        player.auraPlayAudioTuningPresentation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sound and Recovery", systemImage: "dial.high")
                .font(.subheadline.weight(.semibold))

            Picker(
                "EQ Preset",
                selection: Binding(
                    get: { presentation.eqPreset },
                    set: { player.auraPlaySetEQPreset($0) }
                )
            ) {
                ForEach(AuraPlayEQPresetID.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("Changes the equalizer preset for the current audio engine")
            .accessibilityIdentifier(A11yID.AuraPlay.audioTuningEQPreset)

            if presentation.eqPreset == .custom {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(AuraPlayAudioSettings.bandCenters.enumerated()), id: \.offset) { index, center in
                        customEQBandRow(index: index, center: center)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier(A11yID.AuraPlay.audioTuningCustomEQ)
            }

            Toggle(
                "Normalize loudness",
                isOn: Binding(
                    get: { presentation.isNormalizationEnabled },
                    set: { player.auraPlaySetNormalizationEnabled($0) }
                )
            )
            .accessibilityHint("Applies the measured loudness correction when available")
            .accessibilityIdentifier(A11yID.AuraPlay.audioTuningNormalize)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AutoMix")
                    Spacer()
                    Text(crossfadeLabel)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                Slider(
                    value: Binding(
                        get: { presentation.crossfadeDuration },
                        set: { player.auraPlaySetCrossfadeDuration($0) }
                    ),
                    in: 0...8,
                    step: 1
                )
                .accessibilityLabel("AutoMix crossfade")
                .accessibilityValue(crossfadeLabel)
                .accessibilityHint("Sets the crossfade duration for upcoming prepared transitions")
                .accessibilityIdentifier(A11yID.AuraPlay.audioTuningCrossfade)
            }

            AuraPlayCapabilityStatusRow(
                title: "Normalization",
                message: presentation.normalizationStatus,
                systemImage: "waveform",
                status: presentation.isNormalizationEnabled ? "On" : "Off"
            )

            AuraPlayCapabilityStatusRow(
                title: "Transition",
                message: "Gapless preparation uses cached tracks. If the next track is not ready, AuraPlay falls back to a brief gap instead of stalling.",
                systemImage: "arrow.left.and.right",
                status: presentation.transitionStatus
            )

            AuraPlayCapabilityStatusRow(
                title: "Recovery",
                message: "Route changes, interruptions, and buffering events are monitored while playback is active.",
                systemImage: "lifepreserver",
                status: presentation.recoveryStatus
            )

            AuraPlayCapabilityStatusRow(
                title: "Content processing",
                message: "Spoken-word dynamics can engage automatically when content is identified as speech.",
                systemImage: "waveform.and.mic",
                status: presentation.contentProcessingStatus
            )
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private var crossfadeLabel: String {
        let seconds = Int(presentation.crossfadeDuration.rounded())
        return seconds == 0 ? "Off" : "\(seconds) s"
    }

    private func customEQBandRow(index: Int, center: Float) -> some View {
        let gain = Double(presentation.customEQGains[index])
        let bandLabel = AuraPlayAudioSettings.bandLabel(for: center)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bandLabel)
                Spacer()
                Text(String(format: "%+.0f dB", gain))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { Double(presentation.customEQGains[index]) },
                    set: { player.auraPlaySetCustomEQBand(index: index, gain: Float($0)) }
                ),
                in: Double(AuraPlayAudioSettings.minimumBandGain)...Double(AuraPlayAudioSettings.maximumBandGain),
                step: 1
            )
            .accessibilityLabel("\(bandLabel) equalizer gain")
            .accessibilityValue(String(format: "%+.0f decibels", gain))
            .accessibilityIdentifier(A11yID.AuraPlay.audioTuningCustomEQBand(index: index))
        }
    }
}

private struct AuraPlayLiveVisualizerView: View {
    let presentation: AuraPlayVisualizationPresentation
    let reduceMotion: Bool

    @ScaledMetric(relativeTo: .body) private var maxBarHeight = 44
    @ScaledMetric(relativeTo: .body) private var minBarHeight = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Visualizer", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(displayLevels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(presentation.isLive && !reduceMotion ? Color.accentColor.opacity(0.72) : Color.secondary.opacity(0.24))
                        .frame(width: 5, height: minBarHeight + (maxBarHeight * level))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Audio visualizer")
        .accessibilityValue(accessibilityValue)
    }

    private var displayLevels: [Double] {
        if reduceMotion {
            return Array(repeating: 0.16, count: max(presentation.levels.count, 18))
        }
        return presentation.levels
    }

    private var status: String {
        if reduceMotion {
            return "Paused"
        }
        return presentation.isLive ? "Live" : "Paused"
    }

    private var message: String {
        if reduceMotion {
            return "Live meter animation is paused because Reduce Motion is on."
        }
        return presentation.message
    }

    private var accessibilityValue: String {
        if reduceMotion {
            return "Paused for Reduce Motion"
        }
        if presentation.isLive {
            let peak = Int(((presentation.levels.max() ?? 0) * 100).rounded())
            return "Live, peak \(peak) percent"
        }
        return "Paused"
    }
}

private struct AuraPlayCapabilityStatusRow: View {
    let title: String
    let message: String
    let systemImage: String
    let status: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

private extension AuraPlayCachePresentation {
    var title: String {
        switch state {
        case .unavailable:
            "Offline unavailable"
        case .notCached:
            "Online only"
        case .queued:
            "Queued"
        case .downloading, .partial:
            "Downloading"
        case .cached:
            "Saved offline"
        case .pinned:
            "Pinned offline"
        case .error:
            "Offline error"
        }
    }

    var statusLabel: String {
        switch state {
        case .unavailable:
            "Unavailable"
        case .notCached:
            "Online"
        case .queued:
            "Queued"
        case .downloading:
            "Saving"
        case .partial:
            "Partial"
        case .cached:
            "Saved"
        case .pinned:
            "Pinned"
        case .error:
            "Error"
        }
    }

    var accessibilityValue: String {
        guard let progressFraction else {
            return statusLabel
        }
        return "\(Int((progressFraction * 100).rounded())) percent"
    }
}

#if canImport(AVKit) && canImport(UIKit)
private struct AuraPlayAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.accessibilityLabel = "AirPlay"
        view.accessibilityHint = "Choose an AirPlay speaker or device"
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
private struct AuraPlayAudioRoutePicker: View {
    var body: some View {
        Image(systemName: "airplayaudio")
            .foregroundStyle(.secondary)
    }
}
#endif

private struct AuraPlayQueueSheet<Player: AuraPlayPlaybackPresenting>: View {
    let player: Player
    @Environment(\.dismiss) private var dismiss

    private var items: [AuraPlayQueuePresentationItem] {
        player.auraPlayQueueItems()
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Queue Empty",
                        systemImage: "music.note.list",
                        description: Text("Play a track or add one from the library to start a queue.")
                    )
                } else {
                    Section("Playback Queue") {
                        ForEach(items) { item in
                            AuraPlayQueueRow(item: item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if item.role != .current {
                                        Button("Remove", role: .destructive) {
                                            player.auraPlayRemoveQueueItem(id: item.id)
                                        }
                                    }
                                }
                        }
                    }

                    Section {
                        Button("Clear Upcoming", role: .destructive) {
                            player.auraPlayClearUpcomingQueue()
                        }
                    }
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier(A11yID.AuraPlay.queue)
        }
    }
}

private struct AuraPlayQueueRow: View {
    let item: AuraPlayQueuePresentationItem

    var body: some View {
        HStack(spacing: 12) {
            if let imageURLString = item.imageURLString,
               let url = URL(string: imageURLString) {
                CachedAsyncImage(url: url, mediaAccessibility: .decorative)
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "music.note")
                            .accessibilityHidden(true)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(item.artist ?? roleLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(roleLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var roleLabel: String {
        switch item.role {
        case .history:
            "Recent"
        case .current:
            "Now Playing"
        case .upcoming:
            "Upcoming"
        }
    }
}

#Preview("Now Playing Large Text") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Now Playing Dark Mode") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
        .preferredColorScheme(.dark)
}

#Preview("Now Playing High Contrast Large Text") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Now Playing Reduce Transparency") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
}

#Preview("Now Playing Reduce Motion and Transparency") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
}

#Preview("Now Playing Light Increased Contrast") {
    AuraPlayNowPlayingView(player: AuraPlayPreviewPlayer())
        .preferredColorScheme(.light)
}

@MainActor
private final class AuraPlayPreviewPlayer: AuraPlayPlaybackPresenting {
    let auraPlayCurrentTrack: AuraPlayTrack? = AuraPlayTrack(
        id: "preview-current",
        title: "Preview Signal",
        artist: "Auralis QA",
        duration: 245,
        imageURLString: nil
    )
    let auraPlayPlaybackState: AuraPlayPlaybackState = .playing
    let auraPlayProgress: TimeInterval = 72
    let auraPlayNextPreviewTrack: AuraPlayTrack? = AuraPlayTrack(
        id: "preview-next",
        title: "Next Fixture",
        artist: "Auralis QA",
        duration: 198,
        imageURLString: nil
    )
    let auraPlayPreviousPreviewTrack: AuraPlayTrack? = AuraPlayTrack(
        id: "preview-previous",
        title: "Previous Fixture",
        artist: "Auralis QA",
        duration: 211,
        imageURLString: nil
    )

    func auraPlayPlay() throws {}
    func auraPlayPause() {}
    func auraPlayResume() throws {}
    func auraPlaySeek(to time: TimeInterval) throws {}
    func auraPlaySkipForward() {}
    func auraPlaySkipBackward() {}
    func auraPlayNext() async {}
    func auraPlayPrevious() async {}

    func auraPlayRecentlyPlayed(limit: Int) -> [AuraPlayRecentlyPlayedItem] {
        [
            AuraPlayRecentlyPlayedItem(
                id: "recent-preview",
                title: "Recently Played Fixture",
                artist: "Auralis QA",
                imageURLString: nil,
                lastPlayed: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ]
    }

    func auraPlayPlayRecentlyPlayed(id: String) async throws {}
    func auraPlayRemoveRecentlyPlayed(id: String) {}
    func auraPlayClearRecentlyPlayed() {}
    let auraPlayCachePresentation = AuraPlayCachePresentation(
        state: .cached,
        progressFraction: 1,
        message: "Saved offline.",
        canSaveOffline: false,
        canPin: true,
        canUnpin: false
    )
    let auraPlaySystemIntegrationPresentation = AuraPlaySystemIntegrationPresentation(
        routeMode: "Custom Engine",
        nowPlayingStatus: "Active",
        remoteCommandStatus: "Active",
        spatialAudioStatus: "System route only"
    )
    let auraPlayVisualizationPresentation = AuraPlayVisualizationPresentation(
        levels: [0.10, 0.28, 0.54, 0.36, 0.72, 0.42, 0.20, 0.64, 0.48, 0.18, 0.32, 0.58, 0.74, 0.40, 0.24, 0.52, 0.30, 0.16],
        isLive: true,
        message: "Live meter activity from the custom audio engine."
    )
    let auraPlayAudioTuningPresentation = AuraPlayAudioTuningPresentation(
        eqPreset: .bassBoost,
        isNormalizationEnabled: true,
        normalizationStatus: "Approximate loudness measured and applied.",
        crossfadeDuration: 4,
        transitionStatus: "Gapless",
        recoveryStatus: "Ready",
        contentProcessingStatus: "Music dynamics preserved"
    )
    let auraPlayPlaybackAlert: AuraPlayPlaybackAlertPresentation? = nil

    func auraPlayQueueItems() -> [AuraPlayQueuePresentationItem] {
        [
            AuraPlayQueuePresentationItem(
                id: "preview-current",
                title: "Preview Signal",
                artist: "Auralis QA",
                imageURLString: nil,
                role: .current
            )
        ]
    }
    func auraPlayRemoveQueueItem(id: String) {}
    func auraPlayClearUpcomingQueue() {}
    func auraPlaySaveOffline() async {}
    func auraPlayPinOffline() async {}
    func auraPlayUnpinOffline() async {}
    func auraPlaySetEQPreset(_ preset: AuraPlayEQPresetID) {}
    func auraPlaySetCustomEQBand(index: Int, gain: Float) {}
    func auraPlaySetNormalizationEnabled(_ isEnabled: Bool) {}
    func auraPlaySetCrossfadeDuration(_ duration: Double) {}
    func auraPlayDismissPlaybackAlert() {}
    func auraPlayStartVisualization() async {}
    func auraPlayStopVisualization() async {}
}
