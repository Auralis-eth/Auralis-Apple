import Foundation

/// The global application mode. Phase 0 is locked to `.observe`.
public enum AppMode: String, Codable, CaseIterable, Equatable, Sendable {
    case observe = "Observe"
}
