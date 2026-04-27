import UIKit

struct AuraHaptics {
    private let isEnabled: Bool

    init(accessibilityReduceMotion: Bool) {
        self.isEnabled = !accessibilityReduceMotion
    }

    @MainActor
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else {
            return
        }

        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    @MainActor
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else {
            return
        }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    @MainActor
    func selection() {
        guard isEnabled else {
            return
        }

        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
