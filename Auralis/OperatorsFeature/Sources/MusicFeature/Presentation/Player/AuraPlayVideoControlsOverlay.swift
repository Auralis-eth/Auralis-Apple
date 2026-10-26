import AuraUI
import SwiftUI

public struct AuraPlayVideoControlsOverlay<Commander: AuraPlayPlayerCommanding>: View {
    public let capabilities: AuraPlayPlayerVideoCapabilities
    public let commander: Commander
    public let routePicker: AnyView?

    public init(
        capabilities: AuraPlayPlayerVideoCapabilities,
        commander: Commander,
        routePicker: AnyView? = nil
    ) {
        self.capabilities = capabilities
        self.commander = commander
        self.routePicker = routePicker
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { controls }
            VStack(alignment: .leading, spacing: 10) { controls }
        }
        .padding(10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
        .accessibilityIdentifier(A11yID.AuraPlay.playerVideoControls)
    }

    @ViewBuilder
    private var controls: some View {
        if capabilities.isPiPAvailable {
            Button {
                Task {
                    if capabilities.isPiPActive {
                        await commander.restorePiP()
                    } else {
                        await commander.startPiP()
                    }
                }
            } label: {
                Image(systemName: capabilities.isPiPActive ? "pip.exit" : "pip.enter")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(capabilities.isPiPActive ? "Restore picture in picture" : "Start picture in picture")
            .accessibilityIdentifier(A11yID.AuraPlay.playerPiP)
        }

        if capabilities.hasRoutePicker {
            if let routePicker {
                routePicker
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("AirPlay")
                    .accessibilityIdentifier(A11yID.AuraPlay.playerAirPlay)
            } else {
                Image(systemName: "airplayvideo")
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("AirPlay unavailable")
                    .accessibilityIdentifier(A11yID.AuraPlay.playerAirPlay)
            }
        }

        if !capabilities.subtitleOptions.isEmpty || !capabilities.audioDescriptionOptions.isEmpty {
            Menu {
                Button("Subtitles Off") {
                    Task { await commander.selectSubtitle(nil) }
                }
                if !capabilities.subtitleOptions.isEmpty {
                    Section("Subtitles") {
                        ForEach(capabilities.subtitleOptions, id: \.self) { option in
                            Button(option) {
                                Task { await commander.selectSubtitle(option) }
                            }
                        }
                    }
                }
                if !capabilities.audioDescriptionOptions.isEmpty {
                    Section("Audio Descriptions") {
                        ForEach(capabilities.audioDescriptionOptions, id: \.self) { option in
                            Button(option) {
                                Task { await commander.selectSubtitle(option) }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "captions.bubble")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Subtitles")
            .accessibilityIdentifier(A11yID.AuraPlay.playerSubtitles)
        }

        Menu {
            ForEach(capabilities.speedOptions, id: \.self) { speed in
                Button("\(speed, specifier: "%.2g")x") {
                    Task { await commander.setPlaybackSpeed(speed) }
                }
            }
        } label: {
            Text("\(capabilities.selectedSpeed, specifier: "%.2g")x")
                .font(.caption.weight(.bold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Playback speed")
        .accessibilityIdentifier(A11yID.AuraPlay.playerSpeed)

        if capabilities.canChangeAspect {
            Button {
                Task { await commander.toggleVideoGravity() }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Toggle video zoom")
        }
    }
}
