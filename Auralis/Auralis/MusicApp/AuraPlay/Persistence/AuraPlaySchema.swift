import AuralisPrimaryModels
import SwiftData

enum AuraPlaySchema {
    static var models: [any PersistentModel.Type] {
        [
            AuraPlayMediaItem.self,
        ]
    }
}
