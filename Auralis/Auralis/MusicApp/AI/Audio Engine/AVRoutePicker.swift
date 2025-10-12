import SwiftUI
import AVKit

/// A SwiftUI wrapper around `AVRoutePickerView` that keeps the UI in sync with
/// `AVAudioSession` route/mode changes and allows configuring whether video-capable
/// devices are prioritized.
struct AVRoutePicker: UIViewRepresentable {
    var tintColor: UIColor?
    var prioritizesVideoDevices: Bool

    /// Create an AVRoutePicker wrapper.
    /// - Parameters:
    ///   - tintColor: Optional tint color applied to the route picker button.
    ///   - prioritizesVideoDevices: When true, the route picker prioritizes video-capable devices (e.g., AirPlay video targets). Use `true` for video-centric apps (e.g., video players) and `false` for audio/music-focused apps. Defaults to `false`.
    init(tintColor: UIColor? = nil, prioritizesVideoDevices: Bool = false) {
        self.tintColor = tintColor
        self.prioritizesVideoDevices = prioritizesVideoDevices
    }

    class Coordinator {
        weak var view: AVRoutePickerView?
        private var observers: [NSObjectProtocol] = []

        init() {
            let center = NotificationCenter.default
            let session = AVAudioSession.sharedInstance()
            // Route changes (e.g., headphones plugged/unplugged, AirPlay route updates)
            observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] _ in
                self?.refreshView()
            })
            // Interruption changes can also affect availability/selection
            observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] _ in
                self?.refreshView()
            })
            // Media services reset can invalidate session state
            observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
                self?.refreshView()
            })
        }

        deinit {
            let center = NotificationCenter.default
            for token in observers { center.removeObserver(token) }
            observers.removeAll()
        }

        private func refreshView() {
            guard let view else { return }
            // Re-apply properties and ask for layout/display to keep UI in sync.
            // AVRoutePickerView reflects current session route automatically, but
            // nudging layout helps ensure the button state updates promptly.
            view.setNeedsLayout()
            view.setNeedsDisplay()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        if let tintColor { view.tintColor = tintColor }
        view.prioritizesVideoDevices = prioritizesVideoDevices
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        if let tintColor { uiView.tintColor = tintColor }
        uiView.prioritizesVideoDevices = prioritizesVideoDevices
        // Nudge the view to refresh its available routes when external session changes occur
        // (the coordinator will call this method indirectly by re-applying properties).
        uiView.setNeedsLayout()
        uiView.setNeedsDisplay()
    }
}
