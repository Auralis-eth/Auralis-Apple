@testable import Auralis
import Foundation
import Testing

@MainActor
@Suite("Ritual notification settings")
struct RitualNotificationSettingsTests {
    @Test("authorization request refreshes the modeled status")
    func requestRefreshesStatus() async {
        let authorizer = StubRitualNotificationAuthorizer(
            statuses: [.notDetermined, .authorized],
            requestResult: .success(true)
        )
        let model = RitualNotificationSettingsModel(authorizer: authorizer)

        await model.refresh()
        await model.requestAuthorization()

        #expect(model.authorization == .authorized)
        #expect(model.errorMessage == nil)
        #expect(model.isWorking == false)
        #expect(await authorizer.requestCount == 1)
    }

    @Test("authorization errors remain visible and status is refreshed")
    func requestErrorIsVisible() async {
        let authorizer = StubRitualNotificationAuthorizer(
            statuses: [.notDetermined, .denied],
            requestResult: .failure(NotificationTestError.failed)
        )
        let model = RitualNotificationSettingsModel(authorizer: authorizer)

        await model.refresh()
        await model.requestAuthorization()

        #expect(model.authorization == .denied)
        #expect(model.errorMessage?.contains("test notification failure") == true)
        #expect(model.isWorking == false)
    }
}

private enum NotificationTestError: LocalizedError {
    case failed

    var errorDescription: String? { "test notification failure" }
}

private actor StubRitualNotificationAuthorizer: RitualNotificationAuthorizing {
    private var statuses: [RitualNotificationAuthorization]
    private let requestResult: Result<Bool, Error>
    private(set) var requestCount = 0

    init(statuses: [RitualNotificationAuthorization], requestResult: Result<Bool, Error>) {
        self.statuses = statuses
        self.requestResult = requestResult
    }

    func authorizationStatus() -> RitualNotificationAuthorization {
        if statuses.count > 1 {
            return statuses.removeFirst()
        }
        return statuses.first ?? .unknown
    }

    func requestAuthorization() throws -> Bool {
        requestCount += 1
        return try requestResult.get()
    }
}
