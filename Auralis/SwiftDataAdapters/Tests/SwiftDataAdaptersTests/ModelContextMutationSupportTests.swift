import Foundation
import SwiftData
import SwiftDataAdapters
import Testing

@MainActor
@Suite
struct ModelContextMutationSupportTests {
    @Test("rollback-safe mutation saves successful work")
    func rollbackSafeMutationSavesSuccessfulWork() throws {
        let context = try makeContext()

        try context.performRollbackSafeMutation {
            context.insert(SwiftDataAdapterFixture(name: "saved"))
        }

        let fixtures = try context.fetch(FetchDescriptor<SwiftDataAdapterFixture>())
        #expect(fixtures.map(\.name) == ["saved"])
    }

    @Test("rollback-safe mutation rolls back failed inserted work")
    func rollbackSafeMutationRollsBackFailedWork() throws {
        let context = try makeContext()

        #expect(throws: FixtureError.failed) {
            try context.performRollbackSafeMutation {
                context.insert(SwiftDataAdapterFixture(name: "rolled-back"))
                throw FixtureError.failed
            }
        }

        #expect(try context.fetch(FetchDescriptor<SwiftDataAdapterFixture>()).isEmpty)
    }

    @Test("rollback-safe mutation restores existing objects after thrown work")
    func rollbackSafeMutationRestoresExistingObjectsAfterThrownWork() throws {
        let context = try makeContext()
        let fixture = SwiftDataAdapterFixture(name: "original")
        context.insert(fixture)
        try context.save()

        #expect(throws: FixtureError.failed) {
            try context.performRollbackSafeMutation {
                fixture.name = "mutated"
                context.insert(SwiftDataAdapterFixture(name: "inserted"))
                throw FixtureError.failed
            }
        }

        let fixtures = try context.fetch(FetchDescriptor<SwiftDataAdapterFixture>())
        #expect(fixtures.map(\.name) == ["original"])
    }

    @Test("undoable mutation falls back to rollback-safe save without undo manager")
    func undoableMutationFallsBackWithoutUndoManager() throws {
        let context = try makeContext()

        try context.performUndoableMutation(named: "Insert Fixture") {
            context.insert(SwiftDataAdapterFixture(name: "fallback"))
        }

        let fixtures = try context.fetch(FetchDescriptor<SwiftDataAdapterFixture>())
        #expect(fixtures.map(\.name) == ["fallback"])
    }

    @Test("undoable mutation rolls back failed work and closes the undo group")
    func undoableMutationRollsBackFailedWorkWithUndoManager() throws {
        let context = try makeContext()
        let undoManager = UndoManager()
        context.undoManager = undoManager

        #expect(throws: FixtureError.failed) {
            try context.performUndoableMutation(named: "Insert Fixture") {
                context.insert(SwiftDataAdapterFixture(name: "rolled-back"))
                throw FixtureError.failed
            }
        }

        #expect(try context.fetch(FetchDescriptor<SwiftDataAdapterFixture>()).isEmpty)
        #expect(undoManager.groupingLevel == 0)
    }
}

@Model
final class SwiftDataAdapterFixture {
    var name: String

    init(name: String) {
        self.name = name
    }
}

private enum FixtureError: Error {
    case failed
}

private func makeContext() throws -> ModelContext {
    try SwiftDataAdaptersTestModelContainers.context()
}
