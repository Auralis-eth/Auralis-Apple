import Foundation

public struct PendingDeepLinkContext: Equatable {
    public let currentAddress: String
    public let currentAccountAddress: String?
    public let canResolveDeferredLink: Bool
    public let shouldFailDeferredLink: Bool

    public init(
        currentAddress: String,
        currentAccountAddress: String?,
        canResolveDeferredLink: Bool,
        shouldFailDeferredLink: Bool
    ) {
        self.currentAddress = currentAddress
        self.currentAccountAddress = currentAccountAddress
        self.canResolveDeferredLink = canResolveDeferredLink
        self.shouldFailDeferredLink = shouldFailDeferredLink
    }
}
