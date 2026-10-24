import SwiftData
import SwiftDataAdapters

/// Type-erases a domain-owned persistence participant for account-scoped transactions.
///
/// The account store owns the transaction and supplies its `ModelContext`. Domain participants own
/// capture, deletion, and restoration of their models, and must not save or open transactions.
public struct AccountScopedPersistenceParticipant {
    let identifier: String
    private let captureImplementation: (String, ModelContext) throws -> Any
    private let deleteImplementation: (String, ModelContext) throws -> Void
    private let restoreImplementation: (Any, ModelContext) throws -> Void

    public init<Participant: ScopedPersistenceParticipant>(
        identifier: String,
        participant: Participant.Type
    ) where Participant.Scope == String {
        self.identifier = identifier
        self.captureImplementation = { scope, context in
            try participant.capture(scope: scope, in: context)
        }
        self.deleteImplementation = { scope, context in
            try participant.delete(scope: scope, in: context)
        }
        self.restoreImplementation = { snapshot, context in
            guard let typedSnapshot = snapshot as? Participant.Snapshot else {
                throw AccountScopedPersistenceParticipantError.invalidSnapshot(identifier)
            }
            try participant.restore(typedSnapshot, in: context)
        }
    }

    func capture(scope: String, in context: ModelContext) throws -> Any {
        try captureImplementation(scope, context)
    }

    func delete(scope: String, in context: ModelContext) throws {
        try deleteImplementation(scope, context)
    }

    func restore(_ snapshot: Any, in context: ModelContext) throws {
        try restoreImplementation(snapshot, context)
    }
}

private enum AccountScopedPersistenceParticipantError: Error {
    case invalidSnapshot(String)
}
