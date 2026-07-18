import AuralisPrimaryModels
import Foundation

public struct LibraryItemCellViewModel: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let creator: String
    public let collection: String
    public let artworkURL: URL?
    public let artworkURLString: String?
    public let chainBadge: String
    public let chain: Chain
    public let contractAddress: String?
    public let tokenID: String?
    public let duration: String?
    public let mediaType: String
    public let isPlayable: Bool
    public let isCurrent: Bool

    public init(item: AuraPlayMediaItem, isCurrent: Bool = false) {
        self.id = item.sourceNFTID
        self.title = item.title.isEmpty ? "Untitled" : item.title
        self.creator = item.artistName?.isEmpty == false ? item.artistName ?? "Unknown Creator" : "Unknown Creator"
        self.collection = item.collectionName?.isEmpty == false ? item.collectionName ?? "Uncollected" : "Uncollected"
        self.artworkURL = item.artworkURLString.flatMap(URL.init(string:))
        self.artworkURLString = item.artworkURLString
        self.chainBadge = item.chain.routingDisplayName
        self.chain = item.chain
        self.contractAddress = item.contractAddressRawValue
        self.tokenID = item.tokenID
        self.duration = item.durationSeconds.map(Self.durationText)
        self.mediaType = item.hasVideo ? "Video" : "Audio"
        self.isPlayable = item.isPlayable
        self.isCurrent = isCurrent
    }

    public init(queryItem item: MediaItemQueryItem, isCurrent: Bool = false) {
        self.id = item.sourceNFTID
        self.title = item.title.isEmpty ? "Untitled" : item.title
        self.creator = item.artistName?.isEmpty == false ? item.artistName ?? "Unknown Creator" : "Unknown Creator"
        self.collection = item.collectionName?.isEmpty == false ? item.collectionName ?? "Uncollected" : "Uncollected"
        self.artworkURL = item.artworkURLString.flatMap(URL.init(string:))
        self.artworkURLString = item.artworkURLString
        self.chainBadge = item.chain.routingDisplayName
        self.chain = item.chain
        self.contractAddress = item.contractAddress
        self.tokenID = item.tokenID
        self.duration = item.durationSeconds.map(Self.durationText)
        self.mediaType = item.hasVideo ? "Video" : "Audio"
        self.isPlayable = item.isPlayable
        self.isCurrent = isCurrent
    }

    private static func durationText(_ seconds: Double) -> String {
        AuraPlayPlayerTimeFormatter.string(from: seconds)
    }
}

