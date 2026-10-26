import AuralisPrimaryModels
import Foundation

public protocol NativeBalanceProviding: Sendable {
    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance
}
