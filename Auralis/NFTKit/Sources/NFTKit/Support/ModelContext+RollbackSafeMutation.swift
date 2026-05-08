import SwiftData

extension ModelContext {
    public func performRollbackSafeMutation(_ work: () throws -> Void) throws {
        do {
            try work()
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}
