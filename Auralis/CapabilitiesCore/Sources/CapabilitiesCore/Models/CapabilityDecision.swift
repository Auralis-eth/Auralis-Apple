/// Shared decision vocabulary for capability evaluation surfaces.
public enum CapabilityDecision: String, Codable, CaseIterable, Equatable, Sendable {
    case allowed
    case blocked
    case dryRun = "dry_run"
}
