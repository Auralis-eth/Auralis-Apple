import Foundation

public struct AuraPlayCacheSettingsSummary: Equatable, Sendable {
    public let totalBytes: Int64
    public let pinnedBytes: Int64
    public let diskCapBytes: Int64
    public let cachedEntryCount: Int
    public let pinnedEntryCount: Int

    public init(
        totalBytes: Int64,
        pinnedBytes: Int64,
        diskCapBytes: Int64,
        cachedEntryCount: Int,
        pinnedEntryCount: Int
    ) {
        self.totalBytes = totalBytes
        self.pinnedBytes = pinnedBytes
        self.diskCapBytes = diskCapBytes
        self.cachedEntryCount = cachedEntryCount
        self.pinnedEntryCount = pinnedEntryCount
    }
}

public enum AuraPlayCacheSettings {
    public static let diskCapBytesDefaultsKey = "com.auraplay.cache.diskCapBytes"
    public static let minimumDiskCapBytes: Int64 = 200 * 1024 * 1024
    public static let maximumDiskCapBytes: Int64 = 5 * 1024 * 1024 * 1024
    public static let defaultDiskCapBytes: Int64 = 1 * 1024 * 1024 * 1024

    public static func diskCapBytes(from defaults: UserDefaults = .standard) -> Int64 {
        let storedValue = defaults.object(forKey: diskCapBytesDefaultsKey)
        if let intValue = storedValue as? Int {
            return clampedDiskCapBytes(Int64(intValue))
        }
        if let int64Value = storedValue as? Int64 {
            return clampedDiskCapBytes(int64Value)
        }
        if let doubleValue = storedValue as? Double, doubleValue.isFinite {
            return clampedDiskCapBytes(Int64(doubleValue))
        }
        return defaultDiskCapBytes
    }

    public static func storeDiskCapBytes(_ bytes: Int64, in defaults: UserDefaults = .standard) -> Int64 {
        let clampedBytes = clampedDiskCapBytes(bytes)
        defaults.set(clampedBytes, forKey: diskCapBytesDefaultsKey)
        return clampedBytes
    }

    public static func clampedDiskCapBytes(_ bytes: Int64) -> Int64 {
        min(max(bytes, minimumDiskCapBytes), maximumDiskCapBytes)
    }
}
