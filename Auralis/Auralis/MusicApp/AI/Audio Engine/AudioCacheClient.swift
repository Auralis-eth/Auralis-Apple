import Foundation
import AVFoundation

public protocol AudioFileCaching: Sendable {
    func cachedURL(forRemote url: URL) async throws -> URL
    func localURL(forRemote url: URL) async throws -> URL
    func trimMemoryAggressively() async
    func clearAll() async
}

public actor AudioCacheClient: AudioFileCaching {
    public init() {}

    public func cachedURL(forRemote url: URL) async throws -> URL {
        if let u = try await AudioFileCache.shared.cachedURL(forRemote: url) { return u }
        throw URLError(.fileDoesNotExist)
    }

    public func localURL(forRemote url: URL) async throws -> URL {
        try await AudioFileCache.shared.localURL(forRemote: url)
    }

    public func trimMemoryAggressively() async { await AudioFileCache.shared.trimMemoryAggressively() }
    public func clearAll() async { await AudioFileCache.shared.clearAll() }
}
