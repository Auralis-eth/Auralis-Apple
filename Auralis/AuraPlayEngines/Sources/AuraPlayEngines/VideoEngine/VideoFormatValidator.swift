import Foundation

public struct VideoFormatValidator: Sendable {
    public init() {}

    public func validateResolvedPlaybackURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw VideoPlaybackError.unresolvedURL
        }

        if url.pathExtension.lowercased() == "webm" {
            throw VideoPlaybackError.unsupportedVideoFormat
        }
    }
}

public struct VideoBufferingPolicy: Sendable {
    public let gatewayHosts: Set<String>

    public init(gatewayHosts: Set<String> = [
        "ipfs.io",
        "cloudflare-ipfs.com",
        "gateway.pinata.cloud",
        "arweave.net"
    ]) {
        self.gatewayHosts = gatewayHosts
    }

    public func preferredForwardBufferDuration(for url: URL) -> TimeInterval {
        guard let host = url.host?.lowercased() else { return 0 }
        return gatewayHosts.contains(host) ? 10 : 0
    }

    public func isGatewayURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return gatewayHosts.contains(host)
    }
}
