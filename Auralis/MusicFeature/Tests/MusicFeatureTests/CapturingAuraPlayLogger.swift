import Foundation
@testable import MusicFeature

/// Test double for `AuraPlayLogging` that captures emitted events so tests can
/// assert on logging behavior without each suite reinventing an in-memory fake.
final class CapturingAuraPlayLogger: AuraPlayLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AuraPlayLogEvent] = []

    init() {}

    var events: [AuraPlayLogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func events(at level: AuraPlayLogLevel) -> [AuraPlayLogEvent] {
        events.filter { $0.level == level }
    }

    func events(in category: AuraPlayLogCategory) -> [AuraPlayLogEvent] {
        events.filter { $0.category == category }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    func log(_ event: AuraPlayLogEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }
}
