struct PrimaryStoreCopy: Sendable {
    let unavailableAlertTitle: String
    let unavailableFallbackMessage: String

    static let standard = Self(
        unavailableAlertTitle: "Local Storage Unavailable",
        unavailableFallbackMessage: "Auralis could not open local storage on this launch. Changes will not persist after you quit the app."
    )
}
