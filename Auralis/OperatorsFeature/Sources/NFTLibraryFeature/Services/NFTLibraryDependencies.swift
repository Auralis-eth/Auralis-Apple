import AuralisPrimaryModels
import Foundation
import OperatorCore

public struct NFTLibraryDependencies {
    public var openExternalLink: @MainActor (ExternalLinkOpenRequest) async -> Void

    public init(openExternalLink: @escaping @MainActor (ExternalLinkOpenRequest) async -> Void) {
        self.openExternalLink = openExternalLink
    }
}

public struct NFTLibraryActions {
    public var openNFT: @MainActor (String) -> Void
    public var openCollection: @MainActor (String?, String, Chain) -> Void
    public var refresh: @MainActor () async -> Void

    public init(
        openNFT: @escaping @MainActor (String) -> Void,
        openCollection: @escaping @MainActor (String?, String, Chain) -> Void = { _, _, _ in },
        refresh: @escaping @MainActor () async -> Void
    ) {
        self.openNFT = openNFT
        self.openCollection = openCollection
        self.refresh = refresh
    }
}
