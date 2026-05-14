#if canImport(UIKit)
import UIKit

public struct AuraHaptics {
    private let isEnabled: Bool

    public init(accessibilityReduceMotion: Bool) {
        self.isEnabled = !accessibilityReduceMotion
    }

    @MainActor
    public func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else {
            return
        }

        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    @MainActor
    public func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else {
            return
        }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    @MainActor
    public func selection() {
        guard isEnabled else {
            return
        }

        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
#endif
