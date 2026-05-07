import SwiftData

enum AuraPlayMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AuraPlaySchemaV2.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
