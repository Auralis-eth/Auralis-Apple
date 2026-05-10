import Foundation

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
