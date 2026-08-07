import Foundation
import WalletConnectorKit

public enum ReownSDKAvailability {
    public static var isAvailable: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    public static func requireAvailable() throws {
        guard isAvailable else {
            throw WalletConnectionError.unavailable("Reown AppKit adapter is only available on iOS.")
        }
    }
}
