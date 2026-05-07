public struct PrimaryStoreCopy: Sendable {
    public let unavailableAlertTitle: String
    public let unavailableFallbackMessage: String

    public init(
        unavailableAlertTitle: String,
        unavailableFallbackMessage: String
    ) {
        self.unavailableAlertTitle = unavailableAlertTitle
        self.unavailableFallbackMessage = unavailableFallbackMessage
    }
}

public extension PrimaryStoreCopy {
    static let standard = Self(
        unavailableAlertTitle: "Local Storage Unavailable",
        unavailableFallbackMessage: "Auralis could not open local storage on this launch. Changes will not persist after you quit the app."
    )
}
