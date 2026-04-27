import Foundation

/// Produces a synchronous snapshot of the current app context.
///
/// Conformers own their own synchronization. Callers should invoke `snapshot()` from the
/// conformer's expected isolation domain and treat the returned value as an immutable snapshot.
protocol ContextSource {
    func snapshot() -> ContextSnapshot
}
