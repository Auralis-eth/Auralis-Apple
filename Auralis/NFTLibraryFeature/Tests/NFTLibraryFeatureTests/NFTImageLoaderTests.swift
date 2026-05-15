@testable import NFTLibraryFeature
import Foundation
import Testing
import UIKit

@Suite(.serialized)
@MainActor
struct NFTImageLoaderTests {
    @Test("default loaders share the reusable session")
    func defaultLoadersReuseSharedSession() {
        let firstLoader = NFTImageLoader(url: URL(string: "https://example.com/first.png")!)
        let secondLoader = NFTImageLoader(url: URL(string: "https://example.com/second.png")!)

        let firstSession = Mirror(reflecting: firstLoader).descendant("session") as? URLSession
        let secondSession = Mirror(reflecting: secondLoader).descendant("session") as? URLSession

        #expect(firstSession != nil)
        #expect(secondSession != nil)
        #expect(firstSession === secondSession)
        #expect(firstSession === NFTImageLoader.defaultSession)
    }

    @Test("mp4 URL extension rejects immediately and clears loading state")
    func mp4ExtensionRejectClearsLoading() async {
        let loader = NFTImageLoader(url: URL(string: "https://example.com/clip.mp4")!)
        loader.loadIfNeeded()

        await Task.yield()

        #expect(loader.isLoading == false)
        #expect(loader.image == nil)
        if case .videoData = loader.error {
        } else {
            Issue.record("Expected videoData error for mp4 URL extension.")
        }
    }

    @Test("mp4 content type rejects and clears loading state")
    func mp4ContentTypeRejectClearsLoading() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            MockURLProtocol.handler = nil
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/not-an-image")!,
            session: session
        )
        loader.loadIfNeeded()

        for _ in 0..<20 {
            if loader.isLoading == false {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(loader.isLoading == false)
        #expect(loader.image == nil)
        if case .videoData = loader.error {
        } else {
            Issue.record("Expected videoData error for video content type.")
        }
    }

    @Test("HTTP 404 image responses surface a not-found style failure instead of decode noise")
    func notFoundStatusSurfacesSpecificFailure() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (response, Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            MockURLProtocol.handler = nil
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/missing.png")!,
            session: session
        )
        loader.loadIfNeeded()

        try await waitForLoaderToFinish(loader)

        #expect(loader.image == nil)
        if case .badStatus(404) = loader.error {
        } else {
            Issue.record("Expected badStatus(404) for a missing image.")
        }
    }

    @Test("retry succeeds after a transient network failure")
    func retryRecoversAfterNetworkFailure() async throws {
        NFTImageCache.shared.clear()
        let pngData = try #require(
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
                .image { context in
                    UIColor.systemTeal.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
                }
                .pngData()
        )
        var requestCount = 0
        var shouldSucceed = false
        MockURLProtocol.handler = { request in
            requestCount += 1
            if shouldSucceed == false {
                throw URLError(.notConnectedToInternet)
            }

            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (response, pngData)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            MockURLProtocol.handler = nil
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/transient.png")!,
            session: session
        )
        loader.loadIfNeeded()

        try await waitForLoaderToFinish(loader)

        #expect(loader.image == nil)
        if case .offline = loader.error {
        } else {
            Issue.record("Expected offline error after the first failed request.")
        }

        shouldSucceed = true
        loader.retry()

        try await waitForLoaderToFinish(loader)

        #expect(loader.isLoading == false)
        #expect(loader.error == nil)
        #expect(loader.image != nil)
        #expect(requestCount == 2)
    }

    @Test("offline transport failures surface an offline-specific image error")
    func offlineTransportFailureUsesOfflineError() async throws {
        NFTImageCache.shared.clear()
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            MockURLProtocol.handler = nil
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/offline.png")!,
            session: session
        )
        loader.loadIfNeeded()

        try await waitForLoaderToFinish(loader)

        if case .offline = loader.error {
        } else {
            Issue.record("Expected offline image error for not-connected transport failure.")
        }
        #expect(loader.error?.allowsRetry == true)
    }

    @Test("timed out transport failures surface a timeout-specific image error")
    func timedOutTransportFailureUsesTimedOutError() async throws {
        NFTImageCache.shared.clear()
        MockURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            MockURLProtocol.handler = nil
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/timeout.png")!,
            session: session
        )
        loader.loadIfNeeded()

        try await waitForLoaderToFinish(loader)

        if case .timedOut = loader.error {
        } else {
            Issue.record("Expected timedOut image error for timed-out transport failure.")
        }
        #expect(loader.error?.allowsRetry == true)
    }

    @Test("oversized payload reports file-too-large instead of generic invalid data")
    func oversizedPayloadReportsFileTooLarge() async throws {
        NFTImageCache.shared.clear()
        let oversizedData = Data(
            repeating: 0x61,
            count: NFTImageLoader.maxDownloadSizeBytes + 1
        )
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "image/svg+xml",
                    "Content-Length": String(oversizedData.count)
                ]
            )!
            return (response, oversizedData)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            MockURLProtocol.handler = nil
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/oversized.svg")!,
            session: session
        )
        loader.loadIfNeeded()

        try await waitForLoaderToFinish(loader)

        #expect(loader.image == nil)
        if case .fileTooLarge = loader.error {
        } else {
            Issue.record("Expected fileTooLarge for oversized payload.")
        }
    }
}

@MainActor
private func waitForLoaderToFinish(_ loader: NFTImageLoader) async throws {
    for _ in 0..<40 {
        if loader.isLoading == false, loader.image != nil || loader.error != nil {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    Issue.record("Timed out waiting for image loader to finish.")
}

// URLProtocol requires these overridden type methods even on a final class.
private final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (URLResponse, Data)

    // Safety invariant: tests install and clear the handler around a single request flow.
    nonisolated(unsafe) static var handler: Handler?

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.com"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
