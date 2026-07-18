@testable import Auralis
import Foundation
import Testing

struct AuraPlayCacheLaunchConfigurationTests {
    @Test("app launch configuration uses the Phase 5 artwork URLCache capacities")
    func urlCacheCapacityContract() {
        let cache = AppLaunchConfiguration().makeURLCache()

        #expect(cache.memoryCapacity == 50 * 1024 * 1024)
        #expect(cache.diskCapacity == 500 * 1024 * 1024)
    }

    @Test("app launch configuration installs the configured shared URLCache")
    func configureInstallsSharedURLCache() {
        let previousCache = URLCache.shared
        defer { URLCache.shared = previousCache }

        let configuration = AppLaunchConfiguration(
            urlCacheMemoryCapacity: 8 * 1024 * 1024,
            urlCacheDiskCapacity: 64 * 1024 * 1024,
            urlCacheDirectory: nil
        )

        configuration.configure()

        #expect(URLCache.shared.memoryCapacity == 8 * 1024 * 1024)
        #expect(URLCache.shared.diskCapacity == 64 * 1024 * 1024)
    }
}
