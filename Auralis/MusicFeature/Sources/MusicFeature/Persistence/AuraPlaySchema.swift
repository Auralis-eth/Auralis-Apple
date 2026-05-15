import AuralisPrimaryModels
import SwiftData

public enum AuraPlaySchema {
    public static var models: [any PersistentModel.Type] {
        [
            AuraPlayMediaItem.self,
        ]
    }
}
