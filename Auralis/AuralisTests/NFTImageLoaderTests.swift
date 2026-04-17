@testable import Auralis
import Foundation
import Testing

@Suite
@MainActor
struct NFTImageLoaderTests {
    @Test("mp4 URL extension rejects immediately and clears loading state")
    func mp4ExtensionRejectClearsLoading() async {
        let loader = ImageLoader(url: URL(string: "https://example.com/clip.mp4")!)

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
        URLProtocol.registerClass(MockURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(MockURLProtocol.self)
            MockURLProtocol.handler = nil
        }

        let loader = ImageLoader(url: URL(string: "https://example.com/not-an-image")!)

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
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
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
