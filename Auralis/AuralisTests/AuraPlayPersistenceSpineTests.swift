@testable import Auralis
import Foundation
import SwiftData
import Testing

@Suite
struct AuraPlayPersistenceSpineTests {
    @Test("AuraPlay container can construct an in-memory container for the current schema")
    func inMemoryContainerBoots() throws {
        let container = try AppModelContainer.make(inMemory: true)

        #expect(container.migrationPlan == nil)
        #expect(container.schema == Schema(AuraPlaySchema.models))
    }
}
