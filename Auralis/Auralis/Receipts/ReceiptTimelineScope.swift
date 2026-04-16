struct ReceiptTimelineScope: Equatable, Sendable {
    let accountAddress: String
    let chain: Chain

    var displayLabel: String {
        let addressLabel = accountAddress.isEmpty ? "No active account" : accountAddress.displayAddress
        return "\(addressLabel) • \(chain.routingDisplayName)"
    }
}
