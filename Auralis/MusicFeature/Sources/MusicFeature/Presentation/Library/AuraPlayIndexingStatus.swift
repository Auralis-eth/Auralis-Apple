import Foundation

public struct AuraPlayIndexingStatus: Equatable, Sendable {
    public let isActive: Bool
    public let message: String

    public init(isActive: Bool, message: String) {
        self.isActive = isActive
        self.message = message
    }
}
