import AuralisPrimaryModels
import Foundation
import NFTLibraryFeature
import Testing

@Suite
struct NFTLibrarySortTests {
    @Test("sort fields expose expected titles")
    func sortFieldTitles() {
        #expect(NFTLibrarySortField.acquired.title == "Acquired")
        #expect(NFTLibrarySortField.collectionName.title == "Collection Name")
        #expect(NFTLibrarySortField.itemName.title == "Item Name")
    }

    @Test("descriptor preserves requested order")
    func descriptorOrder() {
        #expect(NFTLibrarySortField.acquired.descriptor(order: .reverse).order == .reverse)
        #expect(NFTLibrarySortField.itemName.descriptor(order: .forward).order == .forward)
    }
}
