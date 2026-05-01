import SwiftData

extension ModelContext {
    func performRollbackSafeMutation(_ work: () throws -> Void) throws {
        do {
            try work()
            try save()
        } catch {
            rollback()
            throw error
        }
    }

    @MainActor
    func performUndoableMutation(
        named actionName: String,
        _ work: () throws -> Void
    ) throws {
        guard let undoManager else {
            try performRollbackSafeMutation(work)
            return
        }

        let initialGroupingLevel = undoManager.groupingLevel
        undoManager.beginUndoGrouping()

        do {
            try work()
            try save()
            processPendingChanges()
            undoManager.setActionName(actionName)
            undoManager.endUndoGrouping()
        } catch {
            rollback()
            processPendingChanges()
            if undoManager.groupingLevel > initialGroupingLevel {
                undoManager.endUndoGrouping()
            }
            throw error
        }
    }
}
