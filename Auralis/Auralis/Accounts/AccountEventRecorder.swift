import Foundation

enum AccountEvent: Equatable {
    case added(address: String)
    case removed(address: String)
    case selected(address: String)
}

protocol AccountEventRecorder {
    func record(_ event: AccountEvent)
}

struct NoOpAccountEventRecorder: AccountEventRecorder {
    func record(_ event: AccountEvent) { }
}
