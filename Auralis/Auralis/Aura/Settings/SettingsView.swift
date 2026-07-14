import AuralisPrimaryModels
import SwiftData
import SwiftUI
import AuraUI
import MusicFeature
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    let currentAccountAddress: String
    let currentChain: Chain
    let privacyResetServiceFactory: @MainActor (ModelContext, ModelContainer?) -> any PrivacyResetting
    let auraPlayModelContainer: ModelContainer?
    let playbackRuntime: AuraPlayPlaybackRuntime?
    let onPrivacyResetCompleted: @MainActor () async -> Void

    @State private var isShowingResetConfirmation = false
    @State private var isResettingPrivacyData = false
    @State private var resetErrorMessage: String?
    @State private var resetSuccessMessage: String?
    @State private var customEQGains = AuraPlayAudioSettings.customEQGains()
    @AppStorage(AuraPlayAudioSettings.eqPresetDefaultsKey) private var eqPresetRawValue = AuraPlayEQPresetID.flat.rawValue
    @AppStorage(AuraPlayAudioSettings.normalizationEnabledDefaultsKey) private var isNormalizationEnabled = true
    @AppStorage(AuraPlayAudioSettings.crossfadeDurationDefaultsKey) private var crossfadeDuration = 0.0
    @AppStorage(AuraPlayAudioSettings.downloadForOfflineDefaultsKey) private var downloadsForOffline = false

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
                Text("Clear local privacy and derived support data without deleting saved accounts. This reset clears receipts, search history, ENS cache, gas cache, persisted token holdings, pinned home actions, and saved active wallet selection.")
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
                .disabled(isResettingPrivacyData)

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
        .onAppear {
            syncAudioSettingsFromRuntime()
        }
        .alert("Clear local privacy data?", isPresented: $isShowingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                resetPrivacyData()
            }
        } message: {
            Text("This removes receipts, search history, ENS cache, gas cache, persisted token holdings, pinned home actions, and the saved active wallet selection on this device.")
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
        } else {
            customEQGains = AuraPlayAudioSettings.customEQGains()
            crossfadeDuration = AuraPlayAudioSettings.crossfadeDuration()
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
                    resetErrorMessage = error.localizedDescription
                    AuraAccessibilityAnnouncer.announce(
                        String(localized: "Local privacy data reset failed. \(error.localizedDescription)")
                    )
                }
            }
        }
    }
}
