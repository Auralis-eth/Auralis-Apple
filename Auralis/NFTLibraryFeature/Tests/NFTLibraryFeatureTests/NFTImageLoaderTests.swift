@testable import NFTLibraryFeature
import AuralisTestSupport
import Foundation
import Testing
import UIKit

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class FailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var allowsSuccess = false

    func allowSuccess() {
        lock.lock()
        allowsSuccess = true
        lock.unlock()
    }

    func shouldSucceed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return allowsSuccess
    }
}

@Suite
@MainActor
struct NFTImageLoaderTests {
    @Test("cached image load does not issue a second network request")
    func cachedImageLoadDoesNotIssueSecondNetworkRequest() async throws {
        NFTImageCache.shared.clear()
        let imageURL = try #require(URL(string: "https://example.com/cached.png"))
        let pngData = try #require(
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
                .image { context in
                    UIColor.systemTeal.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
                }
                .pngData()
        )
        let counter = RequestCounter()
        let session = URLSession.mocked { request in
            counter.increment()
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (response, pngData)
        }

        let firstLoader = NFTImageLoader(url: imageURL, session: session)
        try await waitForLoaderToFinish(firstLoader.loadIfNeeded())

        let secondLoader = NFTImageLoader(url: imageURL, session: session)
        let secondLoad = secondLoader.loadIfNeeded()

        _ = try #require(firstLoader.image)
        _ = try #require(secondLoader.image)
        #expect(secondLoad == nil)
        #expect(counter.count == 1)
    }

    @Test("mp4 URL extension rejects immediately and clears loading state")
    func mp4ExtensionRejectClearsLoading() {
        let loader = NFTImageLoader(url: URL(string: "https://example.com/clip.mp4")!)
        loader.loadIfNeeded()

        #expect(loader.isLoading == false)
        #expect(loader.image == nil)
        if case .videoData = loader.error {
        } else {
            Issue.record("Expected videoData error for mp4 URL extension.")
        }
    }

    @Test("mp4 content type rejects and clears loading state")
    func mp4ContentTypeRejectClearsLoading() async throws {
        let session = URLSession.mocked { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "video/mp4"]
            )!
            return (response, Data())
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/not-an-image")!,
            session: session
        )
        let loadingTask = try #require(loader.loadIfNeeded())
        await loadingTask.value

        #expect(loader.isLoading == false)
        #expect(loader.image == nil)
        if case .videoData = loader.error {
        } else {
            Issue.record("Expected videoData error for video content type.")
        }
    }

    @Test("HTTP 404 image responses surface a not-found style failure instead of decode noise")
    func notFoundStatusSurfacesSpecificFailure() async throws {
        let session = URLSession.mocked { request in
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (response, Data())
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/missing.png")!,
            session: session
        )
        try await waitForLoaderToFinish(loader.loadIfNeeded())

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
        let counter = RequestCounter()
        let gate = FailureGate()
        let session = URLSession.mocked { request in
            counter.increment()
            if gate.shouldSucceed() == false {
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

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/transient.png")!,
            session: session
        )
        try await waitForLoaderToFinish(loader.loadIfNeeded())

        #expect(loader.image == nil)
        if case .offline = loader.error {
        } else {
            Issue.record("Expected offline error after the first failed request.")
        }

        gate.allowSuccess()
        try await waitForLoaderToFinish(loader.retry())

        #expect(loader.isLoading == false)
        #expect(loader.error == nil)
        _ = try #require(loader.image)
        #expect(counter.count == 2)
    }

    @Test("offline transport failures surface an offline-specific image error")
    func offlineTransportFailureUsesOfflineError() async throws {
        NFTImageCache.shared.clear()
        let session = URLSession.mocked { _ in
            throw URLError(.notConnectedToInternet)
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/offline.png")!,
            session: session
        )
        try await waitForLoaderToFinish(loader.loadIfNeeded())

        if case .offline = loader.error {
        } else {
            Issue.record("Expected offline image error for not-connected transport failure.")
        }
        #expect(loader.error?.allowsRetry == true)
    }

    @Test("timed out transport failures surface a timeout-specific image error")
    func timedOutTransportFailureUsesTimedOutError() async throws {
        NFTImageCache.shared.clear()
        let session = URLSession.mocked { _ in
            throw URLError(.timedOut)
        }

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/timeout.png")!,
            session: session
        )
        try await waitForLoaderToFinish(loader.loadIfNeeded())

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
        let session = URLSession.mocked { request in
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

        let loader = NFTImageLoader(
            url: URL(string: "https://example.com/oversized.svg")!,
            session: session
        )
        try await waitForLoaderToFinish(loader.loadIfNeeded())

        #expect(loader.image == nil)
        if case .fileTooLarge = loader.error {
        } else {
            Issue.record("Expected fileTooLarge for oversized payload.")
        }
    }
}

@MainActor
private func waitForLoaderToFinish(_ loadingTask: Task<Void, Never>?) async throws {
    let loadingTask = try #require(loadingTask)
    await loadingTask.value
}
