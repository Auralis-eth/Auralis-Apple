import Foundation

@MainActor
final class ObserverBag {
    private var observations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []

    var isEmpty: Bool {
        observations.isEmpty && notificationTokens.isEmpty
    }

    func store(_ observation: NSKeyValueObservation) {
        observations.append(observation)
    }

    func storeNotification(_ token: NSObjectProtocol) {
        notificationTokens.append(token)
    }

    func invalidate() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()

        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        notificationTokens.removeAll()
    }

    deinit {
        MainActor.assumeIsolated {
            observations.forEach { $0.invalidate() }
            notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
