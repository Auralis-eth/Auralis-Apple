import Foundation

/// The global application mode.
///
/// The shipping app is intentionally locked to `.observe`. Do not add Assist or
/// Operate cases until capability grants, user confirmation, provenance checks,
/// and durable receipts are required by the policy gate for every high-risk action.
public enum AppMode: String, Codable, CaseIterable, Equatable, Sendable {
    case observe = "Observe"
}
