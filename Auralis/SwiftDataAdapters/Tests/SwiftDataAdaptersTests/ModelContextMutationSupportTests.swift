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

    @Test("undoable mutation falls back to rollback-safe save without undo manager")
    func undoableMutationFallsBackWithoutUndoManager() throws {
        let context = try makeContext()

        try context.performUndoableMutation(named: "Insert Fixture") {
            context.insert(SwiftDataAdapterFixture(name: "fallback"))
        }

        let fixtures = try context.fetch(FetchDescriptor<SwiftDataAdapterFixture>())
        #expect(fixtures.map(\.name) == ["fallback"])
    }
}

@Model
private final class SwiftDataAdapterFixture {
    var name: String

    init(name: String) {
        self.name = name
    }
}

private enum FixtureError: Error {
    case failed
}

private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema([SwiftDataAdapterFixture.self]),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}
