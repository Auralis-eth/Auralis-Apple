import Foundation

struct PendingDeepLinkContext: Equatable {
    let currentAddress: String
    let currentAccountAddress: String?
    let canResolveDeferredLink: Bool
    let shouldFailDeferredLink: Bool
}
