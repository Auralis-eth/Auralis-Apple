import AuraPlayVideoEngine
import SwiftUI

struct DemoScaffoldView: View {
    @State private var controller = VideoPlayerController()
    @State private var urlText = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
    @State private var statusText = "Idle"
    @State private var lastTickText = "0:00"
    @State private var selectedSpeed: PlaybackSpeedOption = .normal

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                PlayerContainerView(player: controller.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Video preview")

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Resolved HTTPS video URL", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .accessibilityLabel("Resolved video URL")

                    HStack {
                        Button("Load", systemImage: "arrow.down.circle", action: load)
                        Button("Play", systemImage: "play.fill", action: controller.play)
                        Button("Pause", systemImage: "pause.fill", action: controller.pause)

                        Picker("Speed", selection: $selectedSpeed) {
                            ForEach(PlaybackSpeedOption.allCases) { speed in
                                Text(speed.displayLabel).tag(speed)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedSpeed) { _, speed in
                            try? PlaybackSpeedController().setSpeed(speed, on: controller.player)
                        }

                        VideoRoutePickerView()
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("AirPlay")
                    }
                }

                HStack {
                    Label(statusText, systemImage: "waveform.path.ecg")
                    Spacer()
                    Label(lastTickText, systemImage: "clock")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            .frame(minWidth: 420, minHeight: 360)
            .padding()
            .navigationTitle("AuraPlay Video")
            .task {
                await observeEvents()
            }
            .onDisappear {
                // Pause rather than teardown so the view can resume if it reappears.
                controller.pause()
            }
        }
    }

    private func load() {
        guard let url = URL(string: urlText) else {
            statusText = "Invalid URL"
            return
        }

        Task {
            do {
                try await controller.load(resolvedURL: url)
            } catch {
                statusText = error.localizedDescription
            }
        }
    }

    private func observeEvents() async {
        for await event in controller.events {
            switch event {
            case .stateChanged(let state):
                statusText = String(describing: state)
            case .tick(let tick):
                lastTickText = format(seconds: tick.currentSeconds)
            case .didPlayToEnd:
                statusText = "Ended"
            case .failedToPlayToEnd(let message):
                statusText = message ?? "Failed to finish playback"
            case .playbackStalled:
                statusText = "Stalled"
            case .externalPlaybackChanged(let active):
                if active {
                    statusText = "AirPlay active"
                }
            case .waitingReasonChanged(let reason):
                if let reason {
                    statusText = "Waiting: \(reason)"
                }
            }
        }
    }

    private func format(seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}
