import AuralisPrimaryModels
import ReceiptsCore
import SwiftData
import SwiftDataAdapters

@MainActor
public struct SwiftDataReceiptResetService: ReceiptResetting {
    private let modelContext: ModelContext?
    private let receiptStore: any ReceiptStore

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.receiptStore = ReceiptStores.live(modelContext: modelContext)
    }

    public init(receiptStore: any ReceiptStore) {
        self.modelContext = nil
        self.receiptStore = receiptStore
    }

    public func resetReceipts() async throws {
        if let modelContext {
            try modelContext.performRollbackSafeMutation {
                for receipt in try modelContext.fetch(FetchDescriptor<StoredReceipt>()) {
                    modelContext.delete(receipt)
                }
            }
        }

        try await receiptStore.resetAll()
    }
}

@MainActor
public enum ReceiptResetServices {
    public static func live(modelContext: ModelContext) -> SwiftDataReceiptResetService {
        SwiftDataReceiptResetService(modelContext: modelContext)
    }
}
