import AuralisTestSupport
import Foundation
import MusicFeature
import XCTest

final class AuraPlayStorageResolutionShipTests: XCTestCase {
    func testResolverHandlesIPFSArweaveHTTPAndDataURIs() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let resolver = URLResolver(
            configuration: fixtureConfiguration,
            temporaryDirectory: temporaryDirectory
        )

        let ipfsURL = try XCTUnwrap(resolver.resolve("ipfs://QmABC123/track.mp3?download=1#play"))
        XCTAssertEqual(ipfsURL.absoluteString, "https://media.example/ipfs/QmABC123/track.mp3?download=1#play")
        XCTAssertNil(resolver.resolve("ipfs://../escape"))
        XCTAssertNil(resolver.resolve("ipfs://\(String(repeating: "a", count: 513))"))

        let arweaveURL = try XCTUnwrap(resolver.resolve("ar://\(Self.validArweaveID)/track.mp3"))
        XCTAssertEqual(arweaveURL.absoluteString, "https://ar.example/\(Self.validArweaveID)/track.mp3")
        XCTAssertNil(resolver.resolve("ar://short"))

        XCTAssertEqual(
            try XCTUnwrap(resolver.resolve("http://example.com/track.mp3")).absoluteString,
            "https://example.com/track.mp3"
        )
        XCTAssertNil(resolver.resolve("http://example.com:22/file"))

        let dataURL = try XCTUnwrap(resolver.resolve("data:audio/mpeg;base64,Zm9v"))
        XCTAssertTrue(dataURL.isFileURL)
        XCTAssertEqual(dataURL.pathExtension, "mp3")
        XCTAssertEqual(try Data(contentsOf: dataURL), Data("foo".utf8))
        XCTAssertEqual(dataURL, resolver.resolve("data:audio/mpeg;base64,Zm9v"))

        let equivalentPlainURL = try XCTUnwrap(resolver.resolve("data:audio/mpeg,foo"))
        XCTAssertNotEqual(equivalentPlainURL, dataURL)
        XCTAssertEqual(try Data(contentsOf: equivalentPlainURL), Data("foo".utf8))
        XCTAssertNil(resolver.resolve("data:audio/mpeg;base64,!!!notbase64!!!"))
    }

    func testGatewayFallbackChainRetriesFallbacksAndBypassesDataURIs() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        let resolver = URLResolver(
            configuration: fixtureConfiguration,
            temporaryDirectory: temporaryDirectory
        )
        let recorder = RequestRecorder()
        let session = URLSession.mocked { request in
            recorder.record(request)
            let statusCode = request.url?.host == "ipfs-fallback.example" || request.url?.host == "example.com"
                ? 200
                : 503
            return Self.httpResponse(statusCode: statusCode, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: resolver,
            configuration: fixtureConfiguration,
            urlSession: session
        )

        let ipfsURL = try await chain.resolve("ipfs://QmABC123")
        XCTAssertEqual(ipfsURL.host, "ipfs-fallback.example")

        let directURL = try await chain.resolve("https://example.com/track.mp3")
        XCTAssertEqual(directURL.absoluteString, "https://example.com/track.mp3")

        let dataURL = try await chain.resolve("data:audio/mpeg;base64,Zm9v")
        XCTAssertTrue(dataURL.isFileURL)

        XCTAssertEqual(recorder.urls.map(\.host), [
            "media.example",
            "ipfs-fallback.example",
            "example.com"
        ])
        XCTAssertEqual(recorder.methods, ["HEAD", "HEAD", "HEAD"])
    }

    func testGatewayFallbackChainAllowsDownloadsWhenGatewaysRejectHEADOnly() async throws {
        let recorder = RequestRecorder()
        let session = URLSession.mocked { request in
            recorder.record(request)
            let statusCode = request.url?.host == "media.example" ? 405 : 200
            return Self.httpResponse(statusCode: statusCode, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: URLResolver(configuration: fixtureConfiguration),
            configuration: fixtureConfiguration,
            urlSession: session
        )

        let url = try await chain.resolve("ipfs://QmABC123")

        XCTAssertEqual(url.host, "media.example")
        XCTAssertEqual(recorder.urls.map(\.host), ["media.example"])
        XCTAssertEqual(recorder.methods, ["HEAD"])
    }

    func testGatewayFallbackChainPreservesFallbackGatewayBasePaths() async throws {
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

        XCTAssertEqual(ipfsURL.absoluteString, "https://ipfs-fallback.example/gateway/ipfs/QmABC123/track.mp3")
        XCTAssertEqual(arweaveURL.absoluteString, "https://ar-fallback.example/ar-gateway/\(Self.validArweaveID)/track.mp3")
        XCTAssertEqual(recorder.urls.map(\.absoluteString), [
            "https://media.example/root/ipfs/QmABC123/track.mp3",
            "https://ipfs-fallback.example/gateway/ipfs/QmABC123/track.mp3",
            "https://ar.example/base/\(Self.validArweaveID)/track.mp3",
            "https://ar-fallback.example/ar-gateway/\(Self.validArweaveID)/track.mp3"
        ])
    }

    func testGatewayFallbackChainThrowsTypedErrors() async {
        let session = URLSession.mocked { request in
            Self.httpResponse(statusCode: 503, request: request)
        }
        let chain = GatewayFallbackChain(
            resolver: URLResolver(configuration: fixtureConfiguration),
            configuration: fixtureConfiguration,
            urlSession: session
        )

        do {
            _ = try await chain.resolve("xyz://unknown")
            XCTFail("Expected unsupported URI to throw.")
        } catch AuraPlayError.mediaResolution(let message) {
            XCTAssertEqual(message, "Unsupported media URI scheme: xyz://unknown")
        } catch {
            XCTFail("Expected AuraPlayError.mediaResolution, got \(error).")
        }

        do {
            _ = try await chain.resolve("ipfs://QmABC123")
            XCTFail("Expected failed gateways to throw.")
        } catch AuraPlayError.mediaResolution(let message) {
            XCTAssertEqual(message, "All media gateways failed for URI: ipfs://QmABC123")
        } catch {
            XCTFail("Expected AuraPlayError.mediaResolution, got \(error).")
        }
    }

    private static let validArweaveID = "lnGaimJ0PbDfBEAKqBGBJZ3rlrGLVARRKFbNNe9SLHY"

    private var fixtureConfiguration: AuraPlayStorageResolutionConfiguration {
        AuraPlayStorageResolutionConfiguration(
            ipfsGatewayURL: URL(string: "https://media.example"),
            arweaveGatewayURL: URL(string: "https://ar.example"),
            fallbackIPFSGatewayURLs: [URL(string: "https://ipfs-fallback.example")].compactMap { $0 },
            fallbackArweaveGatewayURLs: [URL(string: "https://ar-fallback.example")].compactMap { $0 }
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("auraplay-storage-resolution-ship-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

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
