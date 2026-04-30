import Foundation

/// Development-stage switch between the legacy music experience and the current AuraPlay migration surface.
enum AuraPlayMigrationStage {
    case legacy
    case phase2Persistence

    func resolved(hasAuraPlayPersistence: Bool) -> AuraPlayMigrationStage {
        switch self {
        case .legacy:
            return .legacy
        case .phase2Persistence:
            return hasAuraPlayPersistence ? .phase2Persistence : .legacy
        }
    }
}
