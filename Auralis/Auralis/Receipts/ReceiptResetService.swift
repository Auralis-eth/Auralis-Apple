import Foundation
import SwiftData

@MainActor
protocol ReceiptResetting {
    func resetReceipts() throws
}

@MainActor
struct ReceiptResetService: ReceiptResetting {
    private let receiptStore: any ReceiptStore

    init(receiptStore: any ReceiptStore) {
        self.receiptStore = receiptStore
    }

    func resetReceipts() throws {
        try receiptStore.resetAll()
    }
}

@MainActor
enum ReceiptResetServices {
    static func live(modelContext: ModelContext) -> ReceiptResetService {
        ReceiptResetService(
            receiptStore: ReceiptStores.live(modelContext: modelContext)
        )
    }
}
