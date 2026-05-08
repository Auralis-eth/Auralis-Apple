import Foundation
import SwiftData

@MainActor
public protocol ReceiptResetting {
    func resetReceipts() async throws
}

@MainActor
public struct ReceiptResetService: ReceiptResetting {
    private let receiptStore: any ReceiptStore

    public init(receiptStore: any ReceiptStore) {
        self.receiptStore = receiptStore
    }

    public func resetReceipts() async throws {
        try await receiptStore.resetAll()
    }
}

@MainActor
public enum ReceiptResetServices {
    public static func live(modelContext: ModelContext) -> ReceiptResetService {
        ReceiptResetService(
            receiptStore: ReceiptStores.live(modelContext: modelContext)
        )
    }
}
