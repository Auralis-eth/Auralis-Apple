@testable import Auralis
import Foundation
import SwiftData
import Testing

@Suite
struct AuraPlayPersistenceSpineTests {
    @Test("AuraPlay Phase 2 migration plan can construct an in-memory container")
    func inMemoryContainerBoots() throws {
        let container = try AppModelContainer.make(inMemory: true)

        #expect(container.migrationPlan == AuraPlayMigrationPlan.self)
        #expect(container.schema == Schema(AuraPlaySchemaV2.models))
    }
}
