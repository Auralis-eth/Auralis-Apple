import Foundation

/// Protocol defining a context source providing snapshots.
protocol ContextSource {
    func snapshot() -> ContextSnapshot
}
