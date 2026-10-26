import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation

public enum NFTLibrarySortField: String, CaseIterable, Sendable {
    case acquired
    case collectionName
    case itemName

    public var title: String {
        switch self {
        case .acquired:
            "Acquired"
        case .collectionName:
            "Collection Name"
        case .itemName:
            "Item Name"
        }
    }

    public func descriptor(order: SortOrder = .forward) -> SortDescriptor<NFT> {
        switch self {
        case .acquired:
            SortDescriptor(\NFT.acquiredAt?.blockTimestamp, order: order)
        case .collectionName:
            SortDescriptor(\NFT.collection?.name, order: order)
        case .itemName:
            SortDescriptor(\NFT.name, order: order)
        }
    }
}
