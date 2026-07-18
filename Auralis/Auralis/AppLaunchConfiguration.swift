import Foundation

struct AppLaunchConfiguration {
    let urlCacheMemoryCapacity: Int
    let urlCacheDiskCapacity: Int
    let urlCacheDirectory: URL?

    init(
        urlCacheMemoryCapacity: Int = 50 * 1024 * 1024,
        urlCacheDiskCapacity: Int = 500 * 1024 * 1024,
        urlCacheDirectory: URL? = nil
    ) {
        self.urlCacheMemoryCapacity = urlCacheMemoryCapacity
        self.urlCacheDiskCapacity = urlCacheDiskCapacity
        self.urlCacheDirectory = urlCacheDirectory
    }

    func configure() {
        URLCache.shared = makeURLCache()
    }

    func makeURLCache() -> URLCache {
        URLCache(
            memoryCapacity: urlCacheMemoryCapacity,
            diskCapacity: urlCacheDiskCapacity,
            directory: urlCacheDirectory
        )
    }
}
