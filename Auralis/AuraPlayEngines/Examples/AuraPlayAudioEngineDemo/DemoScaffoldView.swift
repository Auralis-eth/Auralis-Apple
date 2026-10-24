import AuraPlayAudioEngine
import SwiftUI

struct DemoScaffoldView: View {
    @State private var routeMode: AuraPlaybackRouteMode = .customEngine

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback Route") {
                    Picker("Route", selection: $routeMode) {
                        Text("Custom Engine")
                            .tag(AuraPlaybackRouteMode.customEngine)
                        Text("AirPlay Optimized")
                            .tag(AuraPlaybackRouteMode.systemAirPlay)
                    }
                    .pickerStyle(.segmented)

                    RouteModeSummary(routeMode: routeMode)
                }

                Section("AirPlay") {
                    AirPlayRoutePicker()
                        .frame(minHeight: 44)

                    Text("Use AirPlay Optimized when routing to HomePod, AirPlay speakers, Apple TV, or wireless CarPlay and the track does not need AuraPlay's custom EQ, dynamics, or visualization graph.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AuraPlay Engine")
        }
    }
}

private struct RouteModeSummary: View {
    let routeMode: AuraPlaybackRouteMode

    var body: some View {
        Label(summary, systemImage: iconName)
            .font(.body)
            .accessibilityElement(children: .combine)
    }

    private var summary: String {
        switch routeMode {
        case .customEngine:
            "Custom engine keeps EQ, dynamics, visualizers, cache recovery, and gapless scheduling."
        case .systemAirPlay:
            "AirPlay optimized uses AVQueuePlayer for enhanced AirPlay buffering and system route behavior."
        }
    }

    private var iconName: String {
        switch routeMode {
        case .customEngine:
            "slider.horizontal.3"
        case .systemAirPlay:
            "airplayaudio"
        }
    }
}

#if (os(iOS) || os(tvOS)) && canImport(AVKit) && canImport(UIKit)
import AVKit
import UIKit

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .label
        view.activeTintColor = .systemBlue
        view.accessibilityLabel = "AirPlay"
        view.accessibilityHint = "Choose an AirPlay speaker or device."
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
private struct AirPlayRoutePicker: View {
    var body: some View {
        Label("AirPlay picker is available in the iOS or tvOS host app", systemImage: "airplayaudio")
            .font(.body)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
    }
}
#endif
