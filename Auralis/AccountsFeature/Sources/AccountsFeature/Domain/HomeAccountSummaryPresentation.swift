public struct HomeAccountSummaryPresentation: Equatable, Sendable {
    public let title: String
    public let addressLine: String
    public let chainTitle: String
    public let trackedNFTLabel: String
    public let lastActivityLabel: String?

    public init(
        title: String,
        addressLine: String,
        chainTitle: String,
        trackedNFTLabel: String,
        lastActivityLabel: String?
    ) {
        self.title = title
        self.addressLine = addressLine
        self.chainTitle = chainTitle
        self.trackedNFTLabel = trackedNFTLabel
        self.lastActivityLabel = lastActivityLabel
    }
}
