import AuralisTestSupport
import Foundation
@testable import MusicFeature
import Testing

struct StorageResolutionTests {
    @Test("URI scheme detection classifies supported storage inputs")
    func uriSchemeDetection() throws {
        #expect(URIScheme.detect(from: "") == .unknown)
        #expect(URIScheme.detect(from: "   \t\n") == .unknown)
        #expect(URIScheme.detect(from: "ipfs://QmABC") == .ipfsNative(cid: "QmABC"))
        #expect(URIScheme.detect(from: "IPFS://QmABC") == .ipfsNative(cid: "QmABC"))
        #expect(URIScheme.detect(from: "/ipfs/QmABC") == .ipfsPath(cid: "QmABC"))
        #expect(URIScheme.detect(from: "ipfs/QmABC") == .ipfsPath(cid: "QmABC"))
        #expect(URIScheme.detect(from: "ar://\(Self.validArweaveID)") == .arweave(txID: Self.validArweaveID))
        #expect(URIScheme.detect(from: "ftp://old.example") == .unknown)

        if case .http(let url) = URIScheme.detect(from: "http://example.com") {
            #expect(url.absoluteString == "http://example.com")
        } else {
            Issue.record("Expected HTTP URI classification.")
        }

        if case .https(let url) = URIScheme.detect(from: "https://example.com") {
            #expect(url.absoluteString == "https://example.com")
        } else {
            Issue.record("Expected HTTPS URI classification.")
        }

        if case .dataURI(let mimeType, let isBase64, let body) = URIScheme.detect(from: "data:audio/mpeg;base64,Zm9v") {
            #expect(mimeType == "audio/mpeg")
            #expect(isBase64)
            #expect(body == "Zm9v")
        } else {
            Issue.record("Expected data URI classification.")
        }
    }

    @Test("IPFS resolver rewrites native and path URIs through the configured gateway")
    func ipfsResolution() throws {
        let resolver = URLResolver(configuration: Self.fixtureConfiguration)

        let nativeURL = try #require(resolver.resolve("ipfs://QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco"))
        #expect(nativeURL.scheme == "https")
        #expect(nativeURL.host == "media.example")
        #expect(nativeURL.path == "/ipfs/QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco")

        let pathURL = try #require(resolver.resolve("/ipfs/QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco"))
        #expect(pathURL == nativeURL)

        let subpathURL = try #require(resolver.resolve("ipfs://QmABC123/metadata/track.mp3?download=1#play"))
        #expect(subpathURL.path == "/ipfs/QmABC123/metadata/track.mp3")
        #expect(subpathURL.query == "download=1")
        #expect(subpathURL.fragment == "play")

        let unicodeURL = try #require(resolver.resolve("ipfs://QmABC123/文件.mp3"))
        #expect(unicodeURL.absoluteString.contains("%E6%96%87%E4%BB%B6.mp3"))
    }

    @Test("IPFS resolver rejects malformed CIDs")
    func ipfsValidation() {
        let resolver = URLResolver(configuration: Self.fixtureConfiguration)

        #expect(resolver.resolve("ipfs://") == nil)
        #expect(resolver.resolve("ipfs://  ") == nil)
        #expect(resolver.resolve("ipfs://../etc/passwd") == nil)
        #expect(resolver.resolve("ipfs://%2e%2e/escape") == nil)
        #expect(resolver.resolve("ipfs://\(String(repeating: "a", count: 513))") == nil)
    }

    @Test("Arweave resolver validates TX IDs and preserves subpaths")
    func arweaveResolution() throws {
        let resolver = URLResolver(configuration: Self.fixtureConfiguration)

        let url = try #require(resolver.resolve("ar://\(Self.validArweaveID)"))
        #expect(url.host == "ar.example")
        #expect(url.path == "/\(Self.validArweaveID)")

        let subpathURL = try #require(resolver.resolve("ar://\(Self.validArweaveID)/track.mp3"))
        #expect(subpathURL.path == "/\(Self.validArweaveID)/track.mp3")

        #expect(resolver.resolve("ar://") == nil)
        #expect(resolver.resolve("ar://short") == nil)
        #expect(resolver.resolve("ar://\(String(repeating: "a", count: 44))") == nil)
        #expect(resolver.resolve("ar://!!!invalid!!characters!!!!!!!!!!!!!!!") == nil)
        #expect(resolver.resolve("ar://../escape") == nil)
    }

    @Test("HTTP resolver upgrades cleartext URLs and rejects unsafe hosts or ports")
    func httpResolution() throws {
        let resolver = URLResolver(configuration: Self.fixtureConfiguration)

        #expect(try #require(resolver.resolve("http://example.com/track.mp3")).absoluteString == "https://example.com/track.mp3")
        #expect(try #require(resolver.resolve("https://example.com/track.mp3")).absoluteString == "https://example.com/track.mp3")
        #expect(resolver.resolve("http://") == nil)
        #expect(resolver.resolve("https://") == nil)
        #expect(resolver.resolve("http://example.com:22/file") == nil)
        #expect(try #require(resolver.resolve("http://example.com:80/file")).port == 80)
        #expect(try #require(resolver.resolve("http://example.com:443/file")).port == 443)
        #expect(try #require(resolver.resolve("http://example.com:8080/file")).port == 8080)
    }

    @Test("Data URI resolver writes deterministic temporary files")
    func dataURIResolution() throws {
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        let resolver = URLResolver(
            configuration: Self.fixtureConfiguration,
            temporaryDirectory: temporaryDirectory
        )

        let audioURL = try #require(resolver.resolve("data:audio/mpeg;base64,Zm9v"))
        #expect(audioURL.isFileURL)
        #expect(audioURL.pathExtension == "mp3")
        #expect(try Data(contentsOf: audioURL) == Data("foo".utf8))

        let textURL = try #require(resolver.resolve("data:text/plain,hello%20there"))
        #expect(textURL.pathExtension == "bin")
        #expect(try String(contentsOf: textURL, encoding: .utf8) == "hello there")

        let repeatedURL = try #require(resolver.resolve("data:audio/mpeg;base64,Zm9v"))
        #expect(repeatedURL == audioURL)

        let equivalentPlainURL = try #require(resolver.resolve("data:audio/mpeg,foo"))
        #expect(equivalentPlainURL != audioURL)
        #expect(try Data(contentsOf: equivalentPlainURL) == Data("foo".utf8))
        #expect(resolver.resolve("data:audio/mpeg;base64,!!!notbase64!!!") == nil)
    }

    @Test("Gateway fallback chain returns primary URL on first success")
    func gatewayFallbackPrimarySuccess() async throws {
        let recorder = RequestRecorder()
        let session = URLSession.mocked { request in
            recorder.record(request)
            return Self.httpResponse(statusCode: 200, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: URLResolver(configuration: Self.fixtureConfiguration),
            configuration: Self.fixtureConfiguration,
            urlSession: session
        )

        let url = try await chain.resolve("ipfs://QmABC123")

        #expect(url.host == "media.example")
        #expect(recorder.urls.map(\.host) == ["media.example"])
        #expect(recorder.methods == ["HEAD"])
    }

    @Test("Gateway fallback chain retries fallback gateways and reports all-failed errors")
    func gatewayFallbackRetries() async throws {
        let recorder = RequestRecorder()
        let session = URLSession.mocked { request in
            recorder.record(request)
            let statusCode = request.url?.host == "ipfs-fallback.example" ? 200 : 503
            return Self.httpResponse(statusCode: statusCode, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: URLResolver(configuration: Self.fixtureConfiguration),
            configuration: Self.fixtureConfiguration,
            urlSession: session
        )

        let url = try await chain.resolve("ipfs://QmABC123")

        #expect(url.host == "ipfs-fallback.example")
        #expect(recorder.urls.map(\.host) == ["media.example", "ipfs-fallback.example"])
    }

    @Test("Gateway fallback chain allows downloads when gateways reject HEAD only")
    func gatewayFallbackAcceptsHeadOnlyRejections() async throws {
        let recorder = RequestRecorder()
        let session = URLSession.mocked { request in
            recorder.record(request)
            let statusCode = request.url?.host == "media.example" ? 405 : 200
            return Self.httpResponse(statusCode: statusCode, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: URLResolver(configuration: Self.fixtureConfiguration),
            configuration: Self.fixtureConfiguration,
            urlSession: session
        )

        let url = try await chain.resolve("ipfs://QmABC123")

        #expect(url.host == "media.example")
        #expect(recorder.urls.map(\.host) == ["media.example"])
        #expect(recorder.methods == ["HEAD"])
    }

    @Test("Gateway fallback chain preserves fallback gateway base paths")
    func gatewayFallbackPreservesBasePaths() async throws {
        let configuration = AuraPlayStorageResolutionConfiguration(
            ipfsGatewayURL: URL(string: "https://media.example/root"),
            arweaveGatewayURL: URL(string: "https://ar.example/base"),
            fallbackIPFSGatewayURLs: [URL(string: "https://ipfs-fallback.example/gateway")].compactMap { $0 },
            fallbackArweaveGatewayURLs: [URL(string: "https://ar-fallback.example/ar-gateway")].compactMap { $0 }
        )
        let recorder = RequestRecorder()
        let session = URLSession.mocked { request in
            recorder.record(request)
            let statusCode = request.url?.host?.contains("fallback") == true ? 200 : 503
            return Self.httpResponse(statusCode: statusCode, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: URLResolver(configuration: configuration),
            configuration: configuration,
            urlSession: session
        )

        let ipfsURL = try await chain.resolve("ipfs://QmABC123/track.mp3")
        let arweaveURL = try await chain.resolve("ar://\(Self.validArweaveID)/track.mp3")

        #expect(ipfsURL.absoluteString == "https://ipfs-fallback.example/gateway/ipfs/QmABC123/track.mp3")
        #expect(arweaveURL.absoluteString == "https://ar-fallback.example/ar-gateway/\(Self.validArweaveID)/track.mp3")
        #expect(recorder.urls.map(\.absoluteString) == [
            "https://media.example/root/ipfs/QmABC123/track.mp3",
            "https://ipfs-fallback.example/gateway/ipfs/QmABC123/track.mp3",
            "https://ar.example/base/\(Self.validArweaveID)/track.mp3",
            "https://ar-fallback.example/ar-gateway/\(Self.validArweaveID)/track.mp3"
        ])
    }

    @Test("Gateway fallback chain skips recently failed gateways until cache expiry")
    func gatewayHealthCache() async throws {
        let recorder = RequestRecorder()
        let clock = MutableClock(date: Date(timeIntervalSince1970: 100))
        let session = URLSession.mocked { request in
            recorder.record(request)
            let statusCode = request.url?.host == "ipfs-second.example" ? 200 : 503
            return Self.httpResponse(statusCode: statusCode, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: URLResolver(configuration: Self.fixtureConfiguration),
            configuration: Self.fixtureConfigurationWithTwoIPFSFallbacks,
            urlSession: session,
            clock: { clock.date }
        )

        _ = try await chain.resolve("ipfs://QmABC123")
        _ = try await chain.resolve("ipfs://QmABC123")
        clock.date = Date(timeIntervalSince1970: 200)
        _ = try await chain.resolve("ipfs://QmABC123")

        #expect(recorder.urls.map(\.host) == [
            "media.example",
            "ipfs-fallback.example",
            "ipfs-second.example",
            "ipfs-second.example",
            "media.example",
            "ipfs-fallback.example",
            "ipfs-second.example"
        ])
    }

    @Test("Gateway fallback chain bypasses gateway substitution for HTTPS and data URIs")
    func gatewayBypassesDirectURLs() async throws {
        let temporaryDirectory = try Self.makeTemporaryDirectory()
        let recorder = RequestRecorder()
        let session = URLSession.mocked { request in
            recorder.record(request)
            return Self.httpResponse(statusCode: 200, request: request)
        }
        let resolver = URLResolver(
            configuration: Self.fixtureConfiguration,
            temporaryDirectory: temporaryDirectory
        )
        let chain = GatewayFallbackChain(
            resolver: resolver,
            configuration: Self.fixtureConfiguration,
            urlSession: session
        )

        let directURL = try await chain.resolve("https://example.com/track.mp3")
        let dataURL = try await chain.resolve("data:audio/mpeg;base64,Zm9v")

        #expect(directURL.absoluteString == "https://example.com/track.mp3")
        #expect(dataURL.isFileURL)
        #expect(recorder.urls.map(\.absoluteString) == ["https://example.com/track.mp3"])
    }

    @Test("Gateway fallback chain throws typed media resolution errors")
    func gatewayThrowsTypedErrors() async throws {
        let session = URLSession.mocked { request in
            Self.httpResponse(statusCode: 503, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: URLResolver(configuration: Self.fixtureConfiguration),
            configuration: Self.fixtureConfiguration,
            urlSession: session
        )

        await #expect(throws: AuraPlayError.mediaResolution("Unsupported media URI scheme: xyz://unknown")) {
            _ = try await chain.resolve("xyz://unknown")
        }

        await #expect(throws: AuraPlayError.mediaResolution("All media gateways failed for URI: ipfs://QmABC123")) {
            _ = try await chain.resolve("ipfs://QmABC123")
        }
    }

    @Test("URLResolver can be called concurrently without shared mutable state")
    func resolverConcurrentAccess() async {
        let resolver = URLResolver(configuration: Self.fixtureConfiguration)

        await withTaskGroup(of: URL?.self) { group in
            for index in 0..<50 {
                group.addTask {
                    resolver.resolve("ipfs://QmConcurrent\(index)")
                }
            }

            var results: [URL] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }

            #expect(results.count == 50)
            #expect(results.allSatisfy { $0.host == "media.example" })
        }
    }

    private static let validArweaveID = "lnGaimJ0PbDfBEAKqBGBJZ3rlrGLVARRKFbNNe9SLHY"

    private static let fixtureConfiguration = AuraPlayStorageResolutionConfiguration(
        ipfsGatewayURL: URL(string: "https://media.example"),
        arweaveGatewayURL: URL(string: "https://ar.example"),
        fallbackIPFSGatewayURLs: [URL(string: "https://ipfs-fallback.example")].compactMap { $0 },
        fallbackArweaveGatewayURLs: [URL(string: "https://ar-fallback.example")].compactMap { $0 }
    )

    private static let fixtureConfigurationWithTwoIPFSFallbacks = AuraPlayStorageResolutionConfiguration(
        ipfsGatewayURL: URL(string: "https://media.example"),
        arweaveGatewayURL: URL(string: "https://ar.example"),
        fallbackIPFSGatewayURLs: [
            URL(string: "https://ipfs-fallback.example"),
            URL(string: "https://ipfs-second.example")
        ].compactMap { $0 },
        fallbackArweaveGatewayURLs: []
    )

    private static func httpResponse(statusCode: Int, request: URLRequest) -> (URLResponse, Data) {
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data())
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("auraplay-storage-resolution-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var urls: [URL] {
        lock.withLock {
            requests.compactMap(\.url)
        }
    }

    var methods: [String] {
        lock.withLock {
            requests.compactMap(\.httpMethod)
        }
    }

    func record(_ request: URLRequest) {
        lock.withLock {
            requests.append(request)
        }
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDate: Date

    init(date: Date) {
        self.storedDate = date
    }

    var date: Date {
        get {
            lock.withLock {
                storedDate
            }
        }
        set {
            lock.withLock {
                storedDate = newValue
            }
        }
    }
}
