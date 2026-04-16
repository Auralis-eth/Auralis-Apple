import Foundation

protocol NativeBalanceProviding {
    func nativeBalance(for address: String, chain: Chain) async throws -> NativeBalance
}
