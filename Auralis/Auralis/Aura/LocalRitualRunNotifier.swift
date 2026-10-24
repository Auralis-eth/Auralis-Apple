import Foundation
import OSLog
import RuntimeKit
import SocialCore
import UserNotifications

/// Posts ritual outcomes only when the person has already authorized notifications. Permission is
/// requested from an explicit settings/onboarding surface, never as a side effect of a background run.
actor LocalRitualRunNotifier: RitualRunNotifying {
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.auralis", category: "RitualNotifications")

    func notify(ritual: RitualDefinition, status: RuntimeHost.RitualRunStatus) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = ritual.name
        content.body = message(for: status)
        content.sound = status == .failed ? .default : nil
        let request = UNNotificationRequest(
            identifier: "ritual.\(ritual.id).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            logger.error("Unable to deliver ritual notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func message(for status: RuntimeHost.RitualRunStatus) -> String {
        switch status {
        case .completed: "Completed successfully."
        case .partiallyCompleted: "Completed with unavailable or unsuccessful steps."
        case .failed: "Failed. Open Mission Control for details and retry."
        case .skipped: "Skipped because no executable steps were available."
        case .alreadyRunning: "A run is already in progress."
        }
    }
}
