import Foundation
import AVFoundation

public actor Preloader {
    public struct Token: Equatable, Sendable {
        public let nftID: String
        public let url: URL
    }

    private let cache: AudioFileCaching
    private var current: (token: Token, file: AVAudioFile)?

    public init(cache: AudioFileCaching) { self.cache = cache }

    func preload(nft: NFT, url: URL) async {
        do {
            let local: URL
            if url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" {
                local = try await cache.localURL(forRemote: url)
            } else { local = url }
            let file = try AVAudioFile(forReading: local)
            current = (Token(nftID: nft.id, url: local), file)
        } catch {
            current = nil
        }
    }

    func consumeIfMatches(nft: NFT, url: URL) -> AVAudioFile? {
        guard let c = current, c.token.nftID == nft.id && c.token.url == url else { return nil }
        current = nil
        return c.file
    }

    public func cancel() { current = nil }
}
