import Foundation
import SwiftData

@MainActor
protocol ReceiptResetting {
    func resetReceipts() async throws
}

@MainActor
struct ReceiptResetService: ReceiptResetting {
    private let receiptStore: any ReceiptStore

    init(receiptStore: any ReceiptStore) {
        self.receiptStore = receiptStore
    }

    func resetReceipts() async throws {
        try await receiptStore.resetAll()
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
