import AuralisPrimaryModels
import AuraPlayAudioEngine
import AuraPlayVideoEngine
import AuraUI
import Foundation
import MissionControlFeature
import MusicFeature
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import PolicyCore
import ProviderKit
import RuntimeKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    let currentAccountAddress: String
    let currentChain: Chain
    let modeState: ModeState
    let privacyResetServiceFactory: @MainActor (ModelContext, ModelContainer?) -> any PrivacyResetting
    let allWalletDisconnectServiceFactory: @MainActor (ModelContext, ModelContainer?, String?) -> any AllWalletDisconnecting
    let auraPlayModelContainer: ModelContainer?
    let playbackRuntime: AuraPlayPlaybackRuntime?
    let embeddingAvailabilityProvider: any AuraPlayEmbeddingAvailabilityProviding = AuraPlayEmbeddingAvailabilityProvider()
    /// Shared app-lifetime wallet connection, so Social v1 join verification proves ownership through the
    /// same connector as the rest of the app. `nil` falls back to an unverified (local) join.
    var walletConnectionService: AuralisWalletConnectionService?
    let onPrivacyResetCompleted: @MainActor () async -> Void

    @State private var isShowingMissionControl = false
    @State private var isShowingRunGoal = false
    @State private var isShowingSocial = false
    /// Stable for the life of this view, matching `SocialTabView`.
    ///
    /// Previously minted inline in the `.sheet` content closure, so any re-evaluation of `body` while
    /// the sheet was up — and the `.task` blocks below mutate state that causes exactly that — rebuilt
    /// `SocialInviteExchangeView` with a *new* session id against its `@State`-persisted model. Tapping
    /// "Generate invite" again then hosted a second session instead of returning the live invite,
    /// leaving the first session's runtime holding a relay subscription nothing could reach or stop.
    @State private var socialSessionID = UUID()
    @State private var isShowingInAppWallet = false
    @State private var isShowingResetConfirmation = false
    @State private var isShowingDisconnectAllConfirmation = false
    @State private var isResettingPrivacyData = false
    @State private var isDisconnectingAllWallets = false
    @State private var resetErrorMessage: String?
    @State private var resetSuccessMessage: String?
    @State private var embeddingAvailability = AuraPlayEmbeddingAvailability.available
    @State private var customEQGains = AuraPlayAudioSettings.customEQGains()
    @State private var cacheSummary: AuraPlayCacheSettingsSummary?
    @State private var isShowingClearCacheConfirmation = false
    @State private var isClearingCache = false
    @State private var cacheMessage: String?
    @State private var cacheErrorMessage: String?
    @State private var cacheDiskCapBytes = Double(AuraPlayCacheSettings.defaultDiskCapBytes)
    @State private var ritualNotificationSettings = RitualNotificationSettingsModel()
    @AppStorage(AuraPlayAudioSettings.eqPresetDefaultsKey) private var eqPresetRawValue = AuraPlayEQPresetID.flat.rawValue
    @AppStorage(AuraPlayAudioSettings.normalizationEnabledDefaultsKey) private var isNormalizationEnabled = true
    @AppStorage(AuraPlayAudioSettings.crossfadeDurationDefaultsKey) private var crossfadeDuration = 0.0
    @AppStorage(AuraPlayAudioSettings.downloadForOfflineDefaultsKey) private var downloadsForOffline = false
    @AppStorage(AuraPlayIntelligenceSettings.smartShuffleEnabledDefaultsKey) private var isSmartShuffleEnabled = false
    @AppStorage(PlaybackSpeedController.preferenceKey) private var videoPlaybackSpeedRawValue = PlaybackSpeedOption.normal.rawValue
    @AppStorage(AuraPlayPlaybackPreferenceSettings.shuffleModeDefaultsKey) private var shuffleModeRawValue = AuraPlayShuffleMode.off.rawValue
    @AppStorage(AuraPlayPlaybackPreferenceSettings.repeatModeDefaultsKey) private var repeatModeRawValue = AuraPlayRepeatMode.off.rawValue

    private var providerStatuses: [Secrets.ConfigurationStatus] {
        Secrets.configurationStatuses()
    }

    var body: some View {
        List {
            Section("Environment") {
                LabeledContent(
                    "Active Account",
                    value: currentAccountAddress.isEmpty ? "None selected" : currentAccountAddress.displayAddress
                )
                LabeledContent("Chain Scope", value: currentChain.routingDisplayName)
            }

            Section("Wallet") {
                Button {
                    isShowingInAppWallet = true
                } label: {
                    Label("Auralis Wallet", systemImage: "key.horizontal.fill")
                }
                .accessibilityIdentifier("settings.inAppWallet")

                Text("A self-custodial wallet whose keys are generated and stored only on this device, protected by the Secure Enclave and Face ID.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Operator") {
                Button {
                    isShowingMissionControl = true
                } label: {
                    Label("Mission Control", systemImage: "gauge.with.dots.needle.bottom.50percent")
                }
                .accessibilityIdentifier("settings.missionControl")

                Text("Inspect what the operator runtime is doing: live activity, receipts, and the global pause. Crypto stays gated; the rest of Auralis operates fully.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                Button {
                    isShowingRunGoal = true
                } label: {
                    Label("Ask Auralis to Run a Goal", systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings.runGoal")

                Text("State a goal in plain language. Auralis plans it on device and runs the safe steps, pausing for approval before anything changes state. Its reasoning and token usage appear in Mission Control.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Ritual Notifications") {
                LabeledContent("Status", value: ritualNotificationSettings.authorization.description)
                    .accessibilityIdentifier(A11yID.Settings.ritualNotificationStatus)

                if ritualNotificationSettings.authorization.canRequestAuthorization {
                    Button("Enable Ritual Notifications") {
                        Task { await ritualNotificationSettings.requestAuthorization() }
                    }
                    .disabled(ritualNotificationSettings.isWorking)
                    .accessibilityHint("Allows Auralis to report completed, skipped, or failed ritual runs")
                    .accessibilityIdentifier(A11yID.Settings.ritualNotificationEnable)
                } else if ritualNotificationSettings.authorization == .denied {
                    Text("Open System Settings to allow notifications from Auralis.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }

                if let errorMessage = ritualNotificationSettings.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.error)
                        .accessibilityIdentifier(A11yID.Settings.ritualNotificationError)
                }
            }

            // Gated on the relay flag, which is `YES` in *both* the Debug and Release xcconfigs as
            // of 2026-10-12 — so this entry point ships enabled. The gate is a kill switch, not an
            // off-by-default guard; do not read it as evidence that Social is absent in release.
            if SocialFeatureConfiguration().relayEnabled {
                Section("Shared Sessions (Beta)") {
                    Button {
                        isShowingSocial = true
                    } label: {
                        Label("Shared Sessions", systemImage: "person.2.wave.2")
                    }
                    .accessibilityIdentifier("settings.social")

                    Text("Host or join a shared session: generate an invite to hand out, or paste one to join. Encrypted end-to-end; the relay only sees opaque payloads.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Section("AuraPlay Audio") {
                Picker("EQ Preset", selection: eqPresetBinding) {
                    ForEach(AuraPlayEQPresetID.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .accessibilityIdentifier(A11yID.AuraPlay.audioTuningEQPreset)

                if selectedEQPreset == .custom {
                    ForEach(Array(AuraPlayAudioSettings.bandCenters.enumerated()), id: \.offset) { index, center in
                        customEQBandRow(index: index, center: center)
                    }
                }

                Toggle("Normalize loudness", isOn: normalizationBinding)
                    .accessibilityHint("Applies measured loudness correction when AuraPlay has it for a cached track")
                    .accessibilityIdentifier(A11yID.AuraPlay.audioTuningNormalize)

                Toggle("Download for offline", isOn: downloadForOfflineBinding)
                    .accessibilityHint("Pins AuraPlay tracks as they are cached so they stay available offline")
                    .accessibilityIdentifier(A11yID.AuraPlay.audioTuningDownloadOffline)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("AutoMix Crossfade")
                        Spacer()
                        Text(crossfadeLabel)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Slider(value: crossfadeBinding, in: 0...8, step: 1)
                        .accessibilityLabel("AutoMix crossfade")
                        .accessibilityValue(crossfadeLabel)
                        .accessibilityHint("Sets the crossfade duration for upcoming AuraPlay transitions")
                        .accessibilityIdentifier(A11yID.AuraPlay.audioTuningCrossfade)
                }
            }
            .accessibilityIdentifier(A11yID.AuraPlay.settingsAudioTuning)

            Section("AuraPlay Playback") {
                Toggle("Shuffle by default", isOn: shuffleDefaultBinding)
                    .accessibilityHint("Starts AuraPlay queues with shuffle enabled")
                    .accessibilityIdentifier(A11yID.AuraPlay.settingsShuffleDefault)

                Picker("Repeat default", selection: repeatModeBinding) {
                    ForEach(AuraPlayRepeatMode.allCases, id: \.self) { mode in
                        Text(repeatModeTitle(mode)).tag(mode)
                    }
                }
                .accessibilityIdentifier(A11yID.AuraPlay.settingsRepeatDefault)

                Picker("Video speed", selection: videoPlaybackSpeedBinding) {
                    ForEach(PlaybackSpeedOption.allCases) { speed in
                        Text(speed.displayLabel).tag(speed)
                    }
                }
                .accessibilityHint("Sets the default speed for AuraPlay videos")
                .accessibilityIdentifier(A11yID.AuraPlay.settingsVideoSpeed)
            }
            .accessibilityIdentifier(A11yID.AuraPlay.settingsPlayback)

            Section("AuraPlay Storage") {
                LabeledContent("Cache Used", value: cacheUsageLabel)
                    .accessibilityIdentifier(A11yID.AuraPlay.settingsCacheUsage)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cache Limit")
                        Spacer()
                        Text(byteCountLabel(Int64(cacheDiskCapBytes.rounded())))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Slider(
                        value: cacheDiskCapBinding,
                        in: Double(AuraPlayCacheSettings.minimumDiskCapBytes)...Double(AuraPlayCacheSettings.maximumDiskCapBytes),
                        step: Double(100 * 1024 * 1024)
                    )
                    .accessibilityLabel("Cache limit")
                    .accessibilityValue(byteCountLabel(Int64(cacheDiskCapBytes.rounded())))
                    .accessibilityHint("Sets the maximum AuraPlay audio cache size")
                    .accessibilityIdentifier(A11yID.AuraPlay.settingsCacheLimit)
                }

                Button(role: .destructive) {
                    isShowingClearCacheConfirmation = true
                } label: {
                    if isClearingCache {
                        Label("Clearing Cache…", systemImage: "hourglass")
                    } else {
                        Label("Clear Cache", systemImage: "trash")
                    }
                }
                .disabled(isClearingCache)
                .accessibilityHint("Removes cached AuraPlay media that is not pinned for offline playback")
                .accessibilityIdentifier(A11yID.AuraPlay.settingsClearCache)

                if let cacheMessage {
                    Text(cacheMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }

                if let cacheErrorMessage {
                    Text(cacheErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.error)
                }
            }
            .accessibilityIdentifier(A11yID.AuraPlay.settingsStorage)

            Section("AuraPlay Intelligence") {
                Toggle("Smart Shuffle", isOn: smartShuffleBinding)
                    .accessibilityHint("Biases shuffle away from recently played AuraPlay tracks when shuffle is enabled")
                    .accessibilityIdentifier(A11yID.AuraPlay.settingsSmartShuffle)

                if !embeddingAvailability.isAvailable {
                    Label(
                        embeddingAvailability.explanation
                            ?? "Smart playlist features are not available for your device language.",
                        systemImage: "sparkles"
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(A11yID.AuraPlay.settingsEmbeddingUnavailable)
                }
            }
            .accessibilityIdentifier(A11yID.AuraPlay.settingsIntelligence)

            #if DEBUG
            Section("Provider Configuration") {
                AuraTrustLabel(kind: .provider)

                Text("Auralis reads its provider key from Info.plist, which is intended to be populated by xcconfig at build time.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                ForEach(providerStatuses) { status in
                    LabeledContent(status.provider.rawValue) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(status.isConfigured ? "Configured" : "Missing")
                                .foregroundStyle(status.isConfigured ? Color.textPrimary : Color.error)

                            Text(status.sourceDescription)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            #endif

            Section("Privacy") {
                Text("Clear local privacy and derived support data without deleting saved accounts. This reset clears receipts, search history, ENS cache, gas cache, persisted token holdings, shared session and ritual state, pinned home actions, and saved active wallet selection.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                Button(role: .destructive) {
                    isShowingResetConfirmation = true
                } label: {
                    if isResettingPrivacyData {
                        Label("Clearing Local Privacy Data…", systemImage: "hourglass")
                    } else {
                        Label("Clear Local Privacy Data", systemImage: "trash")
                    }
                }
                .disabled(isResettingPrivacyData || isDisconnectingAllWallets)

                Text("Disconnect all wallets and erase local data removes every saved wallet on this device in addition to clearing local AuraPlay, receipt, cache, and search data.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)

                Button(role: .destructive) {
                    isShowingDisconnectAllConfirmation = true
                } label: {
                    if isDisconnectingAllWallets {
                        Label("Disconnecting Wallets…", systemImage: "hourglass")
                    } else {
                        Label("Disconnect All Wallets and Erase Local Data", systemImage: "exclamationmark.triangle")
                    }
                }
                .disabled(isResettingPrivacyData || isDisconnectingAllWallets)
                .accessibilityHint("Removes all saved wallets and clears local Auralis data on this device")
                .accessibilityIdentifier(A11yID.AuraPlay.settingsDisconnectAllWallets)

                if let resetSuccessMessage {
                    Text(resetSuccessMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }

                if let resetErrorMessage {
                    Text(resetErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.error)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingMissionControl) {
            MissionControlTabContainer(
                modelContext: modelContext,
                modeState: modeState,
                activeIdentityID: currentAccountAddress
            )
        }
        .sheet(isPresented: $isShowingInAppWallet) {
            NavigationStack {
                InAppWalletView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingInAppWallet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isShowingRunGoal) {
            NavigationStack {
                MissionControlRunGoalView(
                    host: RuntimeAssembly.sharedHost(
                        modelContext: modelContext,
                        cryptoModeProvider: { modeState.mode },
                        cryptoModeSetter: { modeState.setMode($0) }
                    ),
                    surface: "settings.ask-aura"
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingRunGoal = false }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSocial) {
            NavigationStack {
                SocialInviteExchangeView(
                    composition: SocialAssembly.makeInviteExchange(
                        modelContext: modelContext,
                        modeState: modeState,
                        accountAddress: currentAccountAddress.isEmpty ? nil : currentAccountAddress,
                        chainID: currentChain.chainId,
                        auraPlayModelContainer: auraPlayModelContainer,
                        walletConnectionService: walletConnectionService
                    ),
                    sessionID: socialSessionID
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isShowingSocial = false }
                    }
                }
            }
        }
        .onAppear {
            syncAudioSettingsFromRuntime()
        }
        .task {
            await refreshEmbeddingAvailability()
        }
        .task {
            await refreshCacheSummary()
        }
        .task {
            await ritualNotificationSettings.refresh()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSLocale.currentLocaleDidChangeNotification
            ) {
                await refreshEmbeddingAvailability(force: true)
            }
        }
        .alert("Clear local privacy data?", isPresented: $isShowingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                resetPrivacyData()
            }
        } message: {
            Text("This removes receipts, search history, ENS cache, gas cache, persisted token holdings, pinned home actions, and the saved active wallet selection on this device.")
        }
        .alert("Disconnect all wallets and erase local data?", isPresented: $isShowingDisconnectAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect All", role: .destructive) {
                disconnectAllWalletsAndEraseLocalData()
            }
        } message: {
            Text("This will disconnect every saved wallet, erase local receipts, search history, cached AuraPlay data, token holdings, and wallet selection on this device. This cannot be undone.")
        }
        .alert("Clear AuraPlay cache?", isPresented: $isShowingClearCacheConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Cache", role: .destructive) {
                clearAuraPlayCache()
            }
        } message: {
            Text("This removes downloaded AuraPlay media that is not pinned for offline playback. Pinned items stay available.")
        }
    }

    private var selectedEQPreset: AuraPlayEQPresetID {
        playbackRuntime?.auraPlayAudioTuningPresentation.eqPreset
            ?? AuraPlayEQPresetID(rawValue: eqPresetRawValue)
            ?? .flat
    }

    private var eqPresetBinding: Binding<AuraPlayEQPresetID> {
        Binding(
            get: { selectedEQPreset },
            set: { preset in
                eqPresetRawValue = preset.rawValue
                playbackRuntime?.auraPlaySetEQPreset(preset)
            }
        )
    }

    private var normalizationBinding: Binding<Bool> {
        Binding(
            get: {
                playbackRuntime?.auraPlayAudioTuningPresentation.isNormalizationEnabled
                    ?? isNormalizationEnabled
            },
            set: { isEnabled in
                isNormalizationEnabled = isEnabled
                playbackRuntime?.auraPlaySetNormalizationEnabled(isEnabled)
            }
        )
    }

    private var downloadForOfflineBinding: Binding<Bool> {
        Binding(
            get: { downloadsForOffline },
            set: { isEnabled in
                downloadsForOffline = isEnabled
                if isEnabled {
                    Task { await playbackRuntime?.auraPlayPinOffline() }
                }
            }
        )
    }

    private var smartShuffleBinding: Binding<Bool> {
        Binding(
            get: {
                playbackRuntime?.auraPlaySmartShuffleEnabled ?? isSmartShuffleEnabled
            },
            set: { isEnabled in
                isSmartShuffleEnabled = isEnabled
                playbackRuntime?.auraPlaySetSmartShuffleEnabled(isEnabled)
            }
        )
    }

    private var crossfadeBinding: Binding<Double> {
        Binding(
            get: {
                playbackRuntime?.auraPlayAudioTuningPresentation.crossfadeDuration
                    ?? crossfadeDuration
            },
            set: { duration in
                let clampedDuration = min(8, max(0, duration.rounded()))
                crossfadeDuration = clampedDuration
                playbackRuntime?.auraPlaySetCrossfadeDuration(clampedDuration)
            }
        )
    }

    private var crossfadeLabel: String {
        let seconds = Int(crossfadeDuration.rounded())
        return seconds == 0 ? "Off" : "\(seconds) s"
    }

    private var cacheUsageLabel: String {
        guard let cacheSummary else {
            return "Calculating…"
        }
        return "\(byteCountLabel(cacheSummary.totalBytes)) of \(byteCountLabel(cacheSummary.diskCapBytes))"
    }

    private var shuffleDefaultBinding: Binding<Bool> {
        Binding(
            get: { AuraPlayShuffleMode(rawValue: shuffleModeRawValue) == .on },
            set: { isEnabled in
                shuffleModeRawValue = isEnabled ? AuraPlayShuffleMode.on.rawValue : AuraPlayShuffleMode.off.rawValue
                playbackRuntime?.auraPlaySetShuffleEnabled(isEnabled)
            }
        )
    }

    private var repeatModeBinding: Binding<AuraPlayRepeatMode> {
        Binding(
            get: {
                AuraPlayRepeatMode(rawValue: repeatModeRawValue) ?? .off
            },
            set: { mode in
                repeatModeRawValue = mode.rawValue
                playbackRuntime?.auraPlaySetRepeatMode(mode)
            }
        )
    }

    private var videoPlaybackSpeedBinding: Binding<PlaybackSpeedOption> {
        Binding(
            get: {
                PlaybackSpeedOption(storedRawValue: videoPlaybackSpeedRawValue)
            },
            set: { speed in
                videoPlaybackSpeedRawValue = speed.rawValue
                Task { await playbackRuntime?.auraPlaySetPlaybackSpeed(speed.rawValue) }
            }
        )
    }

    private var cacheDiskCapBinding: Binding<Double> {
        Binding(
            get: { cacheDiskCapBytes },
            set: { value in
                let clampedBytes = AuraPlayCacheSettings.clampedDiskCapBytes(Int64(value.rounded()))
                cacheDiskCapBytes = Double(clampedBytes)
                Task { await updateCacheDiskCap(clampedBytes) }
            }
        )
    }

    private func customEQBandRow(index: Int, center: Float) -> some View {
        let gain = Double(customEQGains[index])
        let bandLabel = AuraPlayAudioSettings.bandLabel(for: center)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bandLabel)
                Spacer()
                Text(String(format: "%+.0f dB", gain))
                    .foregroundStyle(Color.textSecondary)
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { Double(customEQGains[index]) },
                    set: { setCustomEQBand(index: index, gain: Float($0)) }
                ),
                in: Double(AuraPlayAudioSettings.minimumBandGain)...Double(AuraPlayAudioSettings.maximumBandGain),
                step: 1
            )
            .accessibilityLabel("\(bandLabel) equalizer gain")
            .accessibilityValue(String(format: "%+.0f decibels", gain))
            .accessibilityIdentifier(A11yID.AuraPlay.audioTuningCustomEQBand(index: index))
        }
    }

    private func setCustomEQBand(index: Int, gain: Float) {
        guard customEQGains.indices.contains(index) else { return }
        let clampedGain = min(max(gain.rounded(), AuraPlayAudioSettings.minimumBandGain), AuraPlayAudioSettings.maximumBandGain)
        customEQGains[index] = clampedGain
        eqPresetRawValue = AuraPlayEQPresetID.custom.rawValue
        AuraPlayAudioSettings.writeCustomEQGains(customEQGains)
        playbackRuntime?.auraPlaySetCustomEQBand(index: index, gain: clampedGain)
    }

    private func syncAudioSettingsFromRuntime() {
        if let presentation = playbackRuntime?.auraPlayAudioTuningPresentation {
            eqPresetRawValue = presentation.eqPreset.rawValue
            isNormalizationEnabled = presentation.isNormalizationEnabled
            crossfadeDuration = presentation.crossfadeDuration
            customEQGains = presentation.customEQGains
            isSmartShuffleEnabled = playbackRuntime?.auraPlaySmartShuffleEnabled ?? isSmartShuffleEnabled
        } else {
            customEQGains = AuraPlayAudioSettings.customEQGains()
            crossfadeDuration = AuraPlayAudioSettings.crossfadeDuration()
        }
    }

    private func refreshEmbeddingAvailability(force: Bool = false) async {
        embeddingAvailability = force
            ? await embeddingAvailabilityProvider.refreshAvailability()
            : await embeddingAvailabilityProvider.availability()
    }

    private func refreshCacheSummary() async {
        guard let summary = await playbackRuntime?.auraPlayCacheSettingsSummary() else {
            cacheDiskCapBytes = Double(AuraPlayCacheSettings.diskCapBytes())
            return
        }
        cacheSummary = summary
        cacheDiskCapBytes = Double(summary.diskCapBytes)
    }

    private func updateCacheDiskCap(_ bytes: Int64) async {
        do {
            cacheSummary = try await playbackRuntime?.auraPlaySetCacheDiskCapBytes(bytes)
            cacheErrorMessage = nil
        } catch {
            cacheErrorMessage = SettingsErrorPresentation.cacheMessage(for: error)
            AuraAccessibilityAnnouncer.announce(cacheErrorMessage ?? String(localized: "AuraPlay cache update failed."))
        }
    }

    private func clearAuraPlayCache() {
        isClearingCache = true
        cacheMessage = nil
        cacheErrorMessage = nil
        AuraAccessibilityAnnouncer.announce(String(localized: "Clearing AuraPlay cache"))

        Task {
            do {
                let summary = try await playbackRuntime?.auraPlayClearUnpinnedCache()
                await MainActor.run {
                    isClearingCache = false
                    cacheSummary = summary
                    if let summary {
                        cacheDiskCapBytes = Double(summary.diskCapBytes)
                    }
                    let message = String(localized: "AuraPlay cache was cleared. Pinned offline items were kept.")
                    cacheMessage = message
                    AuraAccessibilityAnnouncer.announce(message)
                }
            } catch {
                await MainActor.run {
                    isClearingCache = false
                    cacheErrorMessage = SettingsErrorPresentation.cacheMessage(for: error)
                    AuraAccessibilityAnnouncer.announce(cacheErrorMessage ?? String(localized: "AuraPlay cache clear failed."))
                }
            }
        }
    }

    private func resetPrivacyData() {
        isResettingPrivacyData = true
        resetErrorMessage = nil
        resetSuccessMessage = nil
        AuraAccessibilityAnnouncer.announce(
            String(localized: "Clearing local privacy data")
        )

        Task {
            do {
                try await privacyResetServiceFactory(modelContext, auraPlayModelContainer)
                    .resetLocalPrivacyData()
                await MainActor.run {
                    isResettingPrivacyData = false
                    let successMessage = String(localized: "Local privacy data was cleared for this device.")
                    resetSuccessMessage = successMessage
                    AuraAccessibilityAnnouncer.announce(successMessage)
                }
                await onPrivacyResetCompleted()
            } catch {
                await MainActor.run {
                    isResettingPrivacyData = false
                    resetErrorMessage = SettingsErrorPresentation.privacyResetMessage(for: error)
                    AuraAccessibilityAnnouncer.announce(resetErrorMessage ?? String(localized: "Local privacy data reset failed."))
                }
            }
        }
    }

    private func disconnectAllWalletsAndEraseLocalData() {
        isDisconnectingAllWallets = true
        resetErrorMessage = nil
        resetSuccessMessage = nil
        AuraAccessibilityAnnouncer.announce(
            String(localized: "Disconnecting all wallets and clearing local data")
        )

        Task {
            do {
                try await allWalletDisconnectServiceFactory(
                    modelContext,
                    auraPlayModelContainer,
                    currentAccountAddress.isEmpty ? nil : currentAccountAddress
                )
                .disconnectAllWalletsAndEraseLocalData()
                await MainActor.run {
                    isDisconnectingAllWallets = false
                    let successMessage = String(localized: "All wallets were disconnected and local data was cleared for this device.")
                    resetSuccessMessage = successMessage
                    AuraAccessibilityAnnouncer.announce(successMessage)
                }
                await onPrivacyResetCompleted()
            } catch {
                await MainActor.run {
                    isDisconnectingAllWallets = false
                    resetErrorMessage = SettingsErrorPresentation.allWalletDisconnectMessage(for: error)
                    AuraAccessibilityAnnouncer.announce(resetErrorMessage ?? String(localized: "Wallet disconnect failed."))
                }
            }
        }
    }

    private func repeatModeTitle(_ mode: AuraPlayRepeatMode) -> String {
        switch mode {
        case .off:
            "Off"
        case .one:
            "One"
        case .all:
            "All"
        }
    }

    private func byteCountLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private enum SettingsErrorPresentation {
    static func privacyResetMessage(for error: Error) -> String {
        if let localDataResetError = error as? LocalDataResetError,
           let message = localDataResetError.errorDescription,
           message.isEmpty == false {
            return message
        }
        return String(localized: "Auralis could not clear local privacy data. Please try again.")
    }

    static func cacheMessage(for error: Error) -> String {
        String(localized: "AuraPlay could not update the local cache. Please try again.")
    }

    static func allWalletDisconnectMessage(for error: Error) -> String {
        String(localized: "Auralis could not disconnect every wallet and clear local data. Please try again.")
    }
}
