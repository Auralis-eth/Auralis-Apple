import AuralisPrimaryModels
import Foundation

public enum AccountEvent: Equatable {
    case added(address: String)
    case removed(address: String)
    case selected(address: String)
    case preferredChainChanged(address: String, from: Chain, to: Chain)
    case currentChainChanged(address: String, from: Chain, to: Chain)
}

@MainActor
public protocol AccountEventRecorder {
    func record(_ event: AccountEvent, correlationID: String?) async
}

public extension AccountEventRecorder {
    func record(_ event: AccountEvent) async {
        await record(event, correlationID: nil)
    }
}

@MainActor
public struct NoOpAccountEventRecorder: AccountEventRecorder {
    public init() { }

    public func record(_ event: AccountEvent, correlationID: String?) async { }
}
