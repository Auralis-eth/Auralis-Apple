import Foundation

public protocol ActiveWalletStoring: Sendable {
    func get() -> String?
    func set(_ address: String)
    func clear()
}

public final class UserDefaultsActiveWalletStore: ActiveWalletStoring, @unchecked Sendable {
    public static let defaultKey = "com.auraplay.activeWalletAddress"

    private let userDefaults: UserDefaults
    private let key: String

    public init(userDefaults: UserDefaults = .standard, key: String = UserDefaultsActiveWalletStore.defaultKey) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func get() -> String? {
        userDefaults.string(forKey: key)
    }

    public func set(_ address: String) {
        userDefaults.set(address, forKey: key)
    }

    public func clear() {
        userDefaults.removeObject(forKey: key)
    }
}

public final class InMemoryActiveWalletStore: ActiveWalletStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var address: String?

    public init(address: String? = nil) {
        self.address = address
    }

    public func get() -> String? {
        lock.withLock {
            address
        }
    }

    public func set(_ address: String) {
        lock.withLock {
            self.address = address
        }
    }

    public func clear() {
        lock.withLock {
            address = nil
        }
    }
}
