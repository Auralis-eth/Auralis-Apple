import AuraUI
import Foundation
import ImageIO
import Observation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public final class NFTImageCache: @unchecked Sendable {
    public static let shared = NFTImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1_024 * 1_024
    }

    func set(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func get(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    public func clear() {
        cache.removeAllObjects()
    }
}

@MainActor
@Observable
public final class NFTImageLoader {
    nonisolated private static let maxPixelDimension = 1_024
    nonisolated static let maxDownloadSizeBytes = 20 * 1_024 * 1_024
    nonisolated static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    public enum LoadingError: Error {
        case invalidData
        case offline
        case timedOut
        case networkError
        case badStatus(Int)
        case svgData
        case videoData
        case unsupportedURL
        case fileTooLarge

        var symbolName: String {
            switch self {
            case .invalidData, .svgData:
                "photo.badge.exclamationmark"
            case .offline, .networkError:
                "network.slash"
            case .timedOut:
                "clock.badge.exclamationmark"
            case .badStatus(let statusCode) where statusCode == 404:
                "photo"
            case .badStatus:
                "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
            case .videoData, .unsupportedURL:
                "nosign"
            case .fileTooLarge:
                "exclamationmark.triangle"
            }
        }

        var userMessage: String {
            switch self {
            case .invalidData:
                "Auralis could not decode this image."
            case .offline:
                "You appear to be offline. Reconnect to load this NFT image."
            case .timedOut:
                "The image preview timed out. Try again in a moment."
            case .networkError:
                "Auralis could not load the image right now."
            case .badStatus(let statusCode) where statusCode == 404:
                "This NFT image is no longer available."
            case .badStatus(let statusCode) where statusCode == 429:
                "The image host is rate-limiting previews right now."
            case .badStatus:
                "The image host returned an unexpected response."
            case .svgData:
                "This NFT image format is not supported here yet."
            case .videoData:
                "This NFT preview is video-based."
            case .unsupportedURL:
                "This image source is not supported."
            case .fileTooLarge:
                "This NFT image is too large to preview here."
            }
        }

        var allowsRetry: Bool {
            switch self {
            case .offline, .timedOut, .networkError, .badStatus(429):
                true
            case .badStatus(let statusCode):
                (500...599).contains(statusCode)
            default:
                false
            }
        }
    }

    var image: UIImage?
    var isLoading = false
    var error: LoadingError?

    private var loadingTask: Task<Void, Never>?
    private let url: URL
    private let cacheKey: String
    private let session: URLSession

    init(url: URL, session: URLSession = NFTImageLoader.defaultSession) {
        self.url = url
        self.cacheKey = url.absoluteString
        self.session = session
        image = NFTImageCache.shared.get(for: cacheKey)
    }

    func loadIfNeeded() {
        guard image == nil, !isLoading else { return }
        loadImage()
    }

    func cancel() {
        loadingTask?.cancel()
        loadingTask = nil
        isLoading = false
    }

    func retry() {
        loadImage()
    }

    private func loadImage() {
        loadingTask?.cancel()
        isLoading = true
        image = nil
        error = nil

        guard url.isSupportedRemoteMediaURL else {
            error = .unsupportedURL
            isLoading = false
            return
        }

        guard url.pathExtension.lowercased() != "mp4" else {
            error = .videoData
            isLoading = false
            return
        }

        let currentURL = url
        let currentCacheKey = cacheKey
        loadingTask = Task {
            let result = await Self.fetchImage(url: currentURL, cacheKey: currentCacheKey, session: session)
            guard !Task.isCancelled else { return }
            isLoading = false

            switch result {
            case .success(let image):
                self.image = image
            case .failure(let error):
                self.error = error
            }
        }
    }

    nonisolated private static func fetchImage(
        url: URL,
        cacheKey: String,
        session: URLSession
    ) async -> Result<UIImage, LoadingError> {
        if let cachedImage = NFTImageCache.shared.get(for: cacheKey) {
            return .success(cachedImage)
        }

        do {
            let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return .failure(.badStatus(httpResponse.statusCode))
            }

            if response.isNFTLibraryVideoResponse {
                return .failure(.videoData)
            }

            if response.expectedContentLength > Int64(maxDownloadSizeBytes) {
                return .failure(.fileTooLarge)
            }

            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxDownloadSizeBytes {
                    return .failure(.fileTooLarge)
                }
            }

            return await Task.detached(priority: .userInitiated) {
                if let downloadedImage = downsampledImage(from: data, maxPixelDimension: maxPixelDimension) {
                    NFTImageCache.shared.set(downloadedImage, for: cacheKey)
                    return .success(downloadedImage)
                }

                do {
                    return try data.isNFTLibrarySVGData() ? .failure(.svgData) : .failure(.invalidData)
                } catch NFTLibrarySVGDetectionError.fileTooLarge {
                    return .failure(.fileTooLarge)
                } catch {
                    return .failure(.invalidData)
                }
            }.value
        } catch let error as URLError {
            return .failure(mapTransportError(error))
        } catch {
            return .failure(.networkError)
        }
    }

    nonisolated private static func downsampledImage(from data: Data, maxPixelDimension: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    nonisolated private static func mapTransportError(_ error: URLError) -> LoadingError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            .offline
        case .timedOut:
            .timedOut
        default:
            .networkError
        }
    }
}

public struct NFTCachedAsyncImage: View {
    @State private var loader: NFTImageLoader
    private let url: URL

    public init(url: URL) {
        self.url = url
        _loader = State(initialValue: NFTImageLoader(url: url))
    }

    public var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
            } else if loader.isLoading {
                loadingView
            } else if let error = loader.error {
                errorView(error)
            } else {
                placeholderView
            }
        }
        .task(id: url) {
            loader.loadIfNeeded()
        }
        .onDisappear {
            loader.cancel()
        }
    }

    private var loadingView: some View {
        ZStack {
            Color.surface
                .aspectRatio(1, contentMode: .fit)
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                .scaleEffect(1.5)
        }
        .accessibilityLabel(String(localized: "Loading NFT image"))
    }

    private var placeholderView: some View {
        ZStack {
            Color.surface
                .aspectRatio(1, contentMode: .fit)
            SystemImage("photo")
                .font(.largeTitle)
                .foregroundStyle(Color.textSecondary.opacity(0.3))
                .accessibilityHidden(true)
        }
        .accessibilityLabel(String(localized: "NFT image unavailable"))
    }

    private func errorView(_ error: NFTImageLoader.LoadingError) -> some View {
        ZStack {
            Color.surface
                .aspectRatio(1, contentMode: .fit)
            VStack {
                SystemImage(error.symbolName)
                    .font(.title2)
                    .accessibilityHidden(true)
                SecondaryText(error.userMessage)
                    .multilineTextAlignment(.center)
                if error.allowsRetry {
                    Button("Retry") {
                        loader.retry()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
            }
            .foregroundStyle(Color.error)
            .padding()
        }
        .accessibilityElement(children: .combine)
    }
}
#endif

private enum NFTLibrarySVGDetectionError: Error {
    case fileTooLarge
    case invalidEncoding
}

private enum NFTLibrarySVGConstants {
    static let maxFileSize = 1_048_576
    static let prefixSize = 4_096
    static let pattern = #"<svg\b[^>]*>"#

    static let regex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch {
            assertionFailure("Invalid SVG regex pattern: \(error)")
            return NSRegularExpression()
        }
    }()
}

private extension Data {
    func isNFTLibrarySVGData() throws -> Bool {
        guard !isEmpty else { return false }
        guard count <= NFTLibrarySVGConstants.maxFileSize else {
            throw NFTLibrarySVGDetectionError.fileTooLarge
        }
        guard let string = String(data: prefix(NFTLibrarySVGConstants.prefixSize), encoding: .utf8) else {
            throw NFTLibrarySVGDetectionError.invalidEncoding
        }
        let range = NSRange(location: 0, length: string.utf16.count)
        return NFTLibrarySVGConstants.regex.firstMatch(in: string, options: [], range: range) != nil
    }
}

private extension URLResponse {
    var isNFTLibraryVideoResponse: Bool {
        guard let mimeType = mimeType?.lowercased() else {
            return false
        }

        return mimeType.hasPrefix("video/") || mimeType == "application/mp4"
    }
}

private extension URL {
    var isSupportedRemoteMediaURL: Bool {
        guard let scheme = scheme?.lowercased(),
              let host,
              !host.isEmpty else {
            return false
        }

        return scheme == "https"
    }
}
