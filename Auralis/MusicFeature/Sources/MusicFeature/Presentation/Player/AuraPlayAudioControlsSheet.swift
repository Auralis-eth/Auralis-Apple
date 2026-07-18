import AuraUI
import SwiftUI

public struct AuraPlayAudioControlsSheet<Commander: AuraPlayPlayerCommanding>: View {
    public let capabilities: AuraPlayPlayerAudioCapabilities
    public let commander: Commander

    @Environment(\.dismiss) private var dismiss

    public init(capabilities: AuraPlayPlayerAudioCapabilities, commander: Commander) {
        self.capabilities = capabilities
        self.commander = commander
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("EQ") {
                    Picker(
                        "Preset",
                        selection: Binding(
                            get: { capabilities.tuning.eqPreset },
                            set: { preset in Task { await commander.setEQPreset(preset) } }
                        )
                    ) {
                        ForEach(AuraPlayEQPresetID.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    if capabilities.tuning.eqPreset == .custom {
                        ForEach(Array(AuraPlayAudioSettings.bandCenters.enumerated()), id: \.offset) { index, center in
                            VStack(alignment: .leading) {
                                Text(AuraPlayAudioSettings.bandLabel(for: center))
                                    .font(.caption)
                                Slider(
                                    value: Binding(
                                        get: { Double(capabilities.tuning.customEQGains[index]) },
                                        set: { gain in
                                            Task { await commander.setCustomEQBand(index: index, gain: Float(gain)) }
                                        }
                                    ),
                                    in: -12...12,
                                    step: 0.5
                                )
                                .accessibilityLabel("EQ band \(AuraPlayAudioSettings.bandLabel(for: center))")
                            }
                            .accessibilityIdentifier(A11yID.AuraPlay.audioTuningCustomEQBand(index: index))
                        }
                    }
                }

                Section("Playback") {
                    Toggle(
                        "Normalize loudness",
                        isOn: Binding(
                            get: { capabilities.tuning.isNormalizationEnabled },
                            set: { isEnabled in
                                Task { await commander.setNormalizationEnabled(isEnabled) }
                            }
                        )
                    )

                    VStack(alignment: .leading) {
                        Text("AutoMix \(Int(capabilities.tuning.crossfadeDuration.rounded()))s")
                        Slider(
                            value: Binding(
                                get: { capabilities.tuning.crossfadeDuration },
                                set: { duration in
                                    Task { await commander.setCrossfadeDuration(duration) }
                                }
                            ),
                            in: 0...8,
                            step: 1
                        )
                        .accessibilityLabel("AutoMix crossfade")
                        .accessibilityValue("\(Int(capabilities.tuning.crossfadeDuration.rounded())) seconds")
                    }

                    Text("Normalization uses approximate loudness metadata to target about -14 LUFS when available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Audio Controls")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier(A11yID.AuraPlay.playerAudioControls)
    }
}
