import Foundation
import Observation
import UserNotifications

enum RitualNotificationAuthorization: Equatable, Sendable {
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var description: String {
        switch self {
        case .unknown: "Checking…"
        case .notDetermined: "Not enabled"
        case .denied: "Disabled in System Settings"
        case .authorized: "Enabled"
        case .provisional: "Enabled quietly"
        case .ephemeral: "Enabled temporarily"
        }
    }

    var canRequestAuthorization: Bool { self == .notDetermined }
}

protocol RitualNotificationAuthorizing: Sendable {
    func authorizationStatus() async -> RitualNotificationAuthorization
    func requestAuthorization() async throws -> Bool
}

actor SystemRitualNotificationAuthorizer: RitualNotificationAuthorizing {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> RitualNotificationAuthorization {
        let settings = await center.notificationSettings()
        return switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .unknown
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }
}

@MainActor
@Observable
final class RitualNotificationSettingsModel {
    private let authorizer: any RitualNotificationAuthorizing

    private(set) var authorization: RitualNotificationAuthorization = .unknown
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    init(authorizer: any RitualNotificationAuthorizing = SystemRitualNotificationAuthorizer()) {
        self.authorizer = authorizer
    }

    func refresh() async {
        authorization = await authorizer.authorizationStatus()
    }

    func requestAuthorization() async {
        guard authorization.canRequestAuthorization else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            _ = try await authorizer.requestAuthorization()
            authorization = await authorizer.authorizationStatus()
        } catch {
            errorMessage = "Auralis could not update ritual notifications: \(error.localizedDescription)"
            authorization = await authorizer.authorizationStatus()
        }
    }
}
