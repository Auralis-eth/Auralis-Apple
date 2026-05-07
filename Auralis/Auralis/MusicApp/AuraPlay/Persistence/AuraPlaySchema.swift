import AuralisPrimaryModels
import SwiftData

enum AuraPlaySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AuraPlayWallet.self,
            AuraPlayMediaItem.self,
        ]
    }
}
