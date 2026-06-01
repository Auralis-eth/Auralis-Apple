@testable import NFTLibraryFeature
import AuralisTestSupport
import Foundation
import Testing
import UIKit

@Suite
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
        var requestCount = 0
        var shouldSucceed = false
        let session = URLSession.mocked { request in
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

        shouldSucceed = true
        try await waitForLoaderToFinish(loader.retry())

        #expect(loader.isLoading == false)
        #expect(loader.error == nil)
        #expect(loader.image != nil)
        #expect(requestCount == 2)
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
