import Foundation

struct ERC20TokenDetailPresentation: Equatable {
    let title: String
    let navigationTitle: String
    let symbol: String?
    let amountDisplay: String
    let chainTitle: String
    let scopeTitle: String
    let contractAddress: String
    let updatedLabel: String?
    let isPlaceholder: Bool
    let isAmountHidden: Bool
    let isMetadataStale: Bool
    let isNativeStyleFallback: Bool
    let metadataStatus: String?

    init(route: ERC20TokenRoute, holding: TokenHolding?) {
        let resolvedTitle = Self.cleanedText(holding?.displayName)
            ?? Self.cleanedText(route.symbol)
            ?? "Token Detail"
        let resolvedSymbol = Self.cleanedText(holding?.symbol)
            ?? Self.cleanedText(route.symbol)
        let resolvedAmount = Self.cleanedText(holding?.amountDisplay)
            ?? "Balance unavailable"
        let resolvedContract = Self.cleanedText(holding?.contractAddress)
            ?? route.contractAddress

        self.title = resolvedTitle
        self.navigationTitle = resolvedTitle
        self.symbol = resolvedSymbol
        self.amountDisplay = resolvedAmount
        self.chainTitle = route.chain.routingDisplayName
        self.scopeTitle = "\(route.chain.routingDisplayName) token scope"
        self.contractAddress = resolvedContract
        self.updatedLabel = holding?.updatedAt.formatted(date: .abbreviated, time: .shortened)
        self.isPlaceholder = holding?.isPlaceholder ?? false
        self.isAmountHidden = holding?.hidesAmountUntilMetadataLoads ?? false
        self.isMetadataStale = holding?.hasStaleMetadata ?? false
        self.isNativeStyleFallback = holding?.balanceKind == .native

        if holding == nil {
            self.metadataStatus = "This token route is valid, but a scoped local holding is not currently available."
        } else if isNativeStyleFallback {
            self.metadataStatus = "This screen is using a native-style holding fallback inside the token detail contract."
        } else if isMetadataStale {
            self.metadataStatus = "Cached token metadata is older than the ERC-20 freshness window, so Auralis is refreshing it in the background."
        } else if isAmountHidden {
            self.metadataStatus = "Balance is hidden until token decimals load, so Auralis does not guess at base-unit values."
        } else if isPlaceholder || resolvedSymbol == nil {
            self.metadataStatus = "Some token metadata is still sparse for this holding."
        } else {
            self.metadataStatus = nil
        }
    }

    private static func cleanedText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
