import SwiftData

enum AuraPlaySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            AuraPlayWallet.self,
            AuraPlayNFTToken.self,
            AuraPlayMediaItem.self,
        ]
    }
}
