import AuralisPrimaryModels
import ReceiptsCore
import SwiftData

@MainActor
public struct SwiftDataReceiptResetService: ReceiptResetting {
    private let receiptStore: any ReceiptStore

    public init(modelContext: ModelContext) {
        self.receiptStore = ReceiptStores.live(modelContext: modelContext)
    }

    public init(receiptStore: any ReceiptStore) {
        self.receiptStore = receiptStore
    }

    public func resetReceipts() async throws {
        try await receiptStore.resetAll()
    }
}

@MainActor
public enum ReceiptResetServices {
    public static func live(modelContext: ModelContext) -> SwiftDataReceiptResetService {
        SwiftDataReceiptResetService(modelContext: modelContext)
    }
}
