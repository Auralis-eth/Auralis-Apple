import AuralisPrimaryModels
import AuralisPrimaryPersistence
import SwiftUI

public struct NFTLibrarySortButton: View {
    public let title: String
    public let field: NFTLibrarySortField
    @Binding private var sortOrder: SortDescriptor<NFT>

    public init(title: String, field: NFTLibrarySortField, sortOrder: Binding<SortDescriptor<NFT>>) {
        self.title = title
        self.field = field
        _sortOrder = sortOrder
    }

    public var body: some View {
        Button {
            updateSortOrder()
        } label: {
            if sortOrder.keyPath == field.descriptor().keyPath {
                Label(title, systemImage: sortOrder.order == .forward ? "chevron.down" : "chevron.up")
            } else {
                Label(title, systemImage: "arrow.up.arrow.down")
            }
        }
        .accessibilityValue(sortOrder.keyPath == field.descriptor().keyPath ? selectedAccessibilityValue : "Not selected")
    }

    private var selectedAccessibilityValue: String {
        sortOrder.order == .forward ? "Ascending" : "Descending"
    }

    private func updateSortOrder() {
        if sortOrder.keyPath == field.descriptor().keyPath {
            sortOrder = field.descriptor(order: sortOrder.order == .forward ? .reverse : .forward)
        } else {
            sortOrder = field.descriptor(order: .forward)
        }
    }
}
