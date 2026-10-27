import SwiftData

/// Domain adapter for capturing, deleting, and restoring SwiftData records associated with a scope.
///
/// Implementations must not save, create another context, or open a transaction. The caller owns
/// the transaction boundary and supplies the same context to every participant.
public protocol ScopedPersistenceParticipant {
    associatedtype Scope
    associatedtype Snapshot

    static func capture(scope: Scope, in context: ModelContext) throws -> Snapshot
    static func delete(scope: Scope, in context: ModelContext) throws
    static func restore(_ snapshot: Snapshot, in context: ModelContext) throws
}
