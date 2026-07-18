import SwiftData

extension ModelContext {
    func deleteFetchedModels<T: PersistentModel>(matching descriptor: FetchDescriptor<T> = FetchDescriptor<T>()) throws {
        for model in try fetch(descriptor) {
            delete(model)
        }
    }

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
            processPendingChanges()
            try save()
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
