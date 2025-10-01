import Foundation
import Testing
@testable import Auralis

private final class TestURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }
    static var stubs: [URL: Stub] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stubs[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}

@MainActor
@Suite("AudioFileCache on-disk behavior with protocol stubs")
struct AudioFileCacheTests {
    static var protocolRegistered = false

    static func registerProtocolOnce() {
        guard !protocolRegistered else { return }
        URLProtocol.registerClass(TestURLProtocol.self)
        protocolRegistered = true
    }

    @Test("first download stores file and returns local URL")
    func testInitialDownloadStoresFile() async throws {
        Self.registerProtocolOnce()
        let url = URL(string: "https://test.local/audio1.mp3")!
        let body = Data(repeating: 0xAA, count: 1024)
        TestURLProtocol.stubs[url] = .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg", "ETag": "abc", "Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT"], body: body)

        let local = try await AudioFileCache.shared.localURL(forRemote: url)
        #expect(FileManager.default.fileExists(atPath: local.path))
        let data = try Data(contentsOf: local)
        #expect(data.count == body.count)
    }

    @Test("cachedURL returns stored URL on second lookup")
    func testCachedURLAfterDownload() async throws {
        Self.registerProtocolOnce()
        let url = URL(string: "https://test.local/audio2.mp3")!
        let body = Data(repeating: 0xBB, count: 2048)
        TestURLProtocol.stubs[url] = .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg", "ETag": "def"], body: body)

        _ = try await AudioFileCache.shared.localURL(forRemote: url)
        let cached = try await AudioFileCache.shared.cachedURL(forRemote: url)
        #expect(cached != nil)
        if let cached {
            let data = try Data(contentsOf: cached)
            #expect(data == body)
        }
    }

    @Test("304 Not Modified returns cached without redownload")
    func testConditional304() async throws {
        Self.registerProtocolOnce()
        let url = URL(string: "https://test.local/audio3.mp3")!
        let body = Data(repeating: 0xCC, count: 256)
        TestURLProtocol.stubs[url] = .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg", "ETag": "etag-1", "Last-Modified": "Thu, 22 Oct 2015 07:28:00 GMT"], body: body)

        let first = try await AudioFileCache.shared.localURL(forRemote: url)
        #expect(FileManager.default.fileExists(atPath: first.path))

        // Change stub to 304 and empty body
        TestURLProtocol.stubs[url] = .init(statusCode: 304, headers: ["Content-Type": "audio/mpeg"], body: Data())

        let second = try await AudioFileCache.shared.localURL(forRemote: url)
        #expect(second == first)
    }

    @Test("non-audio MIME is rejected")
    func testMimeValidationRejects() async throws {
        Self.registerProtocolOnce()
        let url = URL(string: "https://test.local/not-audio.bin")!
        let body = Data(repeating: 0xDD, count: 128)
        TestURLProtocol.stubs[url] = .init(statusCode: 200, headers: ["Content-Type": "application/octet-stream"], body: body)

        do {
            _ = try await AudioFileCache.shared.localURL(forRemote: url)
            #expect(false, "Expected non-audio MIME to throw")
        } catch {
            // expected error
        }
    }

    @Test("LRU trimming removes oldest when exceeding cap")
    func testLRUTrimming() async throws {
        let fileManager = FileManager.default
        let cacheDir = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("AudioCache", isDirectory: true)
        try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        // Remove any existing files in test cache dir to isolate test
        let existingFiles = (try? fileManager.contentsOfDirectory(atPath: cacheDir.path)) ?? []
        for file in existingFiles {
            try? fileManager.removeItem(at: cacheDir.appendingPathComponent(file))
        }

        // Create 6 files of 1MB each to exceed 5MB cap (simulate smaller cap environment)
        let files = (0..<6).map { cacheDir.appendingPathComponent("test-\($0)") }
        let chunk = Data(repeating: 0xEE, count: 1_000_000) // 1MB
        for (idx, file) in files.enumerated() {
            try chunk.write(to: file)
            // Touch modification date to simulate LRU order
            var attrs = try fileManager.attributesOfItem(atPath: file.path)
            let date = Date().addingTimeInterval(TimeInterval(-idx * 60))
            attrs[.modificationDate] = date
            try fileManager.setAttributes(attrs, ofItemAtPath: file.path)
        }

        // Stub a small audio file to trigger save and trim in AudioFileCache
        let url = URL(string: "https://test.local/trim.mp3")!
        let smallBody = Data(repeating: 0xAB, count: 16)
        TestURLProtocol.stubs[url] = .init(statusCode: 200, headers: ["Content-Type": "audio/mpeg"], body: smallBody)

        _ = try await AudioFileCache.shared.localURL(forRemote: url)

        let contents = try fileManager.contentsOfDirectory(atPath: cacheDir.path)
        // Expect fewer than original files + 1 (the added trim.mp3) after trim
        #expect(contents.count < files.count + 1)
    }
}
