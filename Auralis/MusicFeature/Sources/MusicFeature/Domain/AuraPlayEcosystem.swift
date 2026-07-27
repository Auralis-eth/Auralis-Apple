import AuralisPrimaryModels
import Foundation

public enum AuraPlayDeepLinkDestination: Equatable, Sendable {
    case playlist(id: String)
    case collection(identifier: String, chain: Chain?)
    case creator(identifier: String)
}

public struct AuraPlayDeepLinkBuilder: Sendable {
    public init() { }

    public func url(for destination: AuraPlayDeepLinkDestination) -> URL? {
        var components = URLComponents()
        components.scheme = "auraplay"

        switch destination {
        case .playlist(let id):
            components.host = "playlist"
            components.path = "/\(id)"

        case .collection(let identifier, let chain):
            components.host = "collection"
            components.path = "/\(identifier)"
            if let chain {
                components.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue)]
            }

        case .creator(let identifier):
            components.host = "creator"
            components.path = "/\(identifier)"
        }

        return components.url
    }
}

public struct AuraPlaySharePolicy: Sendable {
    public let deepLinkBuilder: AuraPlayDeepLinkBuilder

    public init(deepLinkBuilder: AuraPlayDeepLinkBuilder = AuraPlayDeepLinkBuilder()) {
        self.deepLinkBuilder = deepLinkBuilder
    }

    public func mediaShareRequest(
        item: LibraryItemCellViewModel,
        explorerURL: URL?
    ) -> AuraPlayShareRequest {
        AuraPlayShareRequest(
            text: shareText(
                title: item.title,
                creator: item.creator,
                collection: item.collection,
                chain: item.chain.routingDisplayName
            ),
            url: explorerURL,
            artworkURLString: item.artworkURLString
        )
    }

    public func playlistShareRequest(id: String, name: String) -> AuraPlayShareRequest {
        AuraPlayShareRequest(
            text: "\(name) - AuraPlay playlist",
            url: deepLinkBuilder.url(for: .playlist(id: id)),
            artworkURLString: nil
        )
    }

    public func collectionShareRequest(group: LibraryCollectionGroup) -> AuraPlayShareRequest {
        // `group.id` is the composite `"chain|identifier"` key; the deep link
        // handler re-prefixes the chain, so share only the bare identifier to
        // avoid `"chain|chain|identifier"` (ADR-007).
        let identifier = Self.nonEmpty(group.contractAddress)
            ?? Self.bareIdentifier(fromGroupID: group.id, chain: group.chain)
        return AuraPlayShareRequest(
            text: "\(group.collectionName) - \(group.itemCount) AuraPlay media items on \(group.chain.routingDisplayName)",
            url: deepLinkBuilder.url(for: .collection(identifier: identifier, chain: group.chain)),
            artworkURLString: group.artworkURLStrings.first
        )
    }

    public func creatorShareRequest(profile: AuraPlayCreatorProfile) -> AuraPlayShareRequest {
        AuraPlayShareRequest(
            text: "\(profile.displayName) - \(profile.itemCount) AuraPlay media items",
            url: deepLinkBuilder.url(for: .creator(identifier: profile.id)),
            artworkURLString: profile.items.compactMap(\.artworkURLString).first
        )
    }

    public func creatorShareRequest(group: LibraryCreatorGroup) -> AuraPlayShareRequest {
        AuraPlayShareRequest(
            text: "\(group.displayName) - \(group.itemCount) AuraPlay media items",
            url: deepLinkBuilder.url(for: .creator(identifier: group.id)),
            artworkURLString: group.artworkURLStrings.first
        )
    }

    private func shareText(title: String, creator: String, collection: String, chain: String) -> String {
        [title, creator, collection, chain]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Drops the leading `"<chain>|"` segment from a composite collection group ID
    /// so a shared link carries only the identifier the handler will re-qualify.
    private static func bareIdentifier(fromGroupID id: String, chain: Chain) -> String {
        let prefix = "\(chain.rawValue)|"
        if id.hasPrefix(prefix) {
            return String(id.dropFirst(prefix.count))
        }
        return id
    }
}

public struct AuraPlayProvenancePresentation: Equatable, Sendable {
    public let title: String
    public let chainName: String
    public let contractAddress: String?
    public let tokenID: String?
    public let tokenType: String?
    public let collectionName: String?
    public let explorerURL: URL?

    public init(
        title: String,
        chainName: String,
        contractAddress: String?,
        tokenID: String?,
        tokenType: String?,
        collectionName: String?,
        explorerURL: URL?
    ) {
        self.title = title
        self.chainName = chainName
        self.contractAddress = contractAddress
        self.tokenID = tokenID
        self.tokenType = tokenType
        self.collectionName = collectionName
        self.explorerURL = explorerURL
    }

    public init(item: LibraryItemCellViewModel, explorerURL: URL?) {
        self.init(
            title: item.title,
            chainName: item.chain.routingDisplayName,
            contractAddress: Self.nonEmpty(item.contractAddress),
            tokenID: Self.nonEmpty(item.tokenID),
            tokenType: Self.nonEmpty(item.tokenType),
            collectionName: Self.nonEmpty(item.collection),
            explorerURL: explorerURL
        )
    }

    public init(item: AuraPlayCurrentItemPresentation) {
        self.init(
            title: item.title,
            chainName: Self.nonEmpty(item.chainDisplayName) ?? "Unknown Chain",
            contractAddress: Self.nonEmpty(item.contractAddress),
            tokenID: Self.nonEmpty(item.tokenID),
            tokenType: nil,
            collectionName: Self.nonEmpty(item.collection),
            explorerURL: item.explorerURL
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension AuraPlayProvenancePresentation: Identifiable {
    public var id: String {
        [
            title,
            chainName,
            contractAddress ?? "no-contract",
            tokenID ?? "no-token"
        ].joined(separator: "|")
    }
}
