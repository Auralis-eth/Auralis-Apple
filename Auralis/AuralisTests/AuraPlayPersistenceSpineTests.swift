@testable import Auralis
import Foundation
import MusicFeature
import SwiftData
import Testing

struct AuraPlayPersistenceSpineTests {
    @Test("AuraPlay container can construct an in-memory container for the current schema")
    func inMemoryContainerBoots() throws {
        let container = try AuraPlayModelContainer.make(inMemory: true)

        #expect(container.migrationPlan != nil)
        #expect(container.schema == Schema(versionedSchema: AuraPlaySchemaV2.self))
    }
}
