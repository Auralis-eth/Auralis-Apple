import SwiftData

enum AuraPlayMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AuraPlaySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
