//
//  NFTImageView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import ImageIO
import SwiftUI

// NSCache is internally synchronized for concurrent access, so this wrapper is
// safe to share across tasks even though UIImage itself is not Sendable.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Configure cache limits
        cache.countLimit = 100 // Adjust based on your app's needs
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }

    func set(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func get(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

// Image Loader that handles caching
@MainActor
final class ImageLoader: ObservableObject {
    nonisolated private static let maxPixelDimension = 1_024
    nonisolated static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    enum LoadingError: Error {
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
                return "photo.badge.exclamationmark"
            case .offline, .networkError:
                return "network.slash"
            case .timedOut:
                return "clock.badge.exclamationmark"
            case .badStatus(let statusCode) where statusCode == 404:
                return "photo"
            case .badStatus:
                return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
            case .videoData, .unsupportedURL:
                return "nosign"
            case .fileTooLarge:
                return "exclamationmark.triangle"
            }
        }

        var userMessage: String {
            switch self {
            case .invalidData:
                return "Auralis could not decode this image."
            case .offline:
                return "You appear to be offline. Reconnect to load this NFT image."
            case .timedOut:
                return "The image preview timed out. Try again in a moment."
            case .networkError:
                return "Auralis could not load the image right now."
            case .badStatus(let statusCode) where statusCode == 404:
                return "This NFT image is no longer available."
            case .badStatus(let statusCode) where statusCode == 429:
                return "The image host is rate-limiting previews right now."
            case .badStatus:
                return "The image host returned an unexpected response."
            case .svgData:
                return "This NFT image format is not supported here yet."
            case .videoData:
                return "This NFT preview is video-based."
            case .unsupportedURL:
                return "This image source is not supported."
            case .fileTooLarge:
                return "This NFT image is too large to preview here."
            }
        }

        var allowsRetry: Bool {
            switch self {
            case .offline, .timedOut, .networkError, .badStatus(429):
                return true
            case .badStatus(let statusCode):
                return (500...599).contains(statusCode)
            default:
                return false
            }
        }
    }
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var error: LoadingError?

    private var loadingTask: Task<Void, Never>?
    let url: URL
    private let cacheKey: String
    private let session: URLSession

    init(
        url: URL,
        session: URLSession = ImageLoader.defaultSession
    ) {
        self.url = url
        self.cacheKey = url.absoluteString
        self.session = session

        if let cachedImage = ImageCache.shared.get(for: cacheKey) {
            self.image = cachedImage
        }
    }

    func loadIfNeeded() {
        guard image == nil, !isLoading else {
            return
        }
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
            if let cachedImage = ImageCache.shared.get(for: currentCacheKey) {
                guard !Task.isCancelled else { return }
                image = cachedImage
                isLoading = false
                return
            }

            let result = await Self.fetchImage(
                url: currentURL,
                cacheKey: currentCacheKey,
                session: session
            )
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

    func cancel() {
        loadingTask?.cancel()
        loadingTask = nil
        isLoading = false
    }

    func retry() {
        loadImage()
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
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    nonisolated private static func fetchImage(
        url: URL,
        cacheKey: String,
        session: URLSession
    ) async -> Result<UIImage, LoadingError> {
        if let cachedImage = ImageCache.shared.get(for: cacheKey) {
            return .success(cachedImage)
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard !Task.isCancelled else { return .failure(.networkError) }

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return .failure(.badStatus(httpResponse.statusCode))
            }

            if let httpResponse = response as? HTTPURLResponse,
               let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? httpResponse.value(forHTTPHeaderField: "Content-Type") {
                let content = contentType.lowercased()
                if content.contains("video/mp4") || content.contains("video/mpeg4") {
                    return .failure(.videoData)
                }
            }

            return await Task.detached(priority: .userInitiated) {
                if let downloadedImage = downsampledImage(from: data, maxPixelDimension: maxPixelDimension) {
                    ImageCache.shared.set(downloadedImage, for: cacheKey)
                    return .success(downloadedImage)
                }

                do {
                    if try data.isSVGData() {
                        return .failure(.svgData)
                    }
                } catch SVGDetectionError.fileTooLarge {
                    return .failure(.fileTooLarge)
                } catch {
                    return .failure(.invalidData)
                }

                return .failure(.invalidData)
            }.value
        } catch let error as URLError {
            return .failure(mapTransportError(error))
        } catch {
            return .failure(.networkError)
        }
    }

    nonisolated private static func mapTransportError(_ error: URLError) -> LoadingError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .networkError
        }
    }
}

// Cached async image view
struct CachedAsyncImage: View {
    @StateObject private var loader: ImageLoader
    private let url: URL

    init(url: URL) {
        self.url = url
        _loader = StateObject(wrappedValue: ImageLoader(url: url))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
            } else if loader.isLoading {
                ZStack {
                    Color.surface
                        .aspectRatio(1, contentMode: .fit)
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                        .scaleEffect(1.5)
                }
            } else if let error = loader.error {
                ZStack {
                    Color.surface
                        .aspectRatio(1, contentMode: .fit)
                    VStack {
                        SystemImage(error.symbolName)
                            .font(.title2)
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
            } else {
                ZStack {
                    Color.surface
                        .aspectRatio(1, contentMode: .fit)
                    SystemImage("photo")
                        .font(.largeTitle)
                        .foregroundStyle(Color.textSecondary.opacity(0.3))
                }
            }
        }
        .task(id: url) {
            loader.loadIfNeeded()
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

enum SVGConstants {
    static let maxFileSize: Int = 1_048_576 // 1MB, prevents excessive memory usage
    static let prefixSize: Int = 4096 // 4KB, covers typical SVG headers (XML prologs, comments)
    static let svgTagPrefix: String = "<svg"
    static let pattern: String = #"<svg\b[^>]*>"#

    static let regex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch {
            assertionFailure("Invalid SVG regex pattern: \(error)")
            return NSRegularExpression()
        }
    }()
}

/// Errors for exceptional conditions during SVG detection.
enum SVGDetectionError: Error {
    case fileTooLarge
    case invalidEncoding
}

/// Determines if the provided data represents an SVG file by checking for a valid `<svg>` tag.
/// - Parameter data: The input data to check, expected to be UTF-8 encoded.
/// - Returns: `true` if the data starts with a valid SVG opening tag, `false` if it’s empty or not an SVG.
/// - Throws: `SVGDetectionError.fileTooLarge` if the data exceeds 1MB; `SVGDetectionError.invalidEncoding` if UTF-8 decoding fails.
/// - Note: Checks only the first 4KB to optimize performance and memory usage, sufficient for most SVG files as the `<svg>` tag typically appears early. May produce false negatives for rare cases where the tag appears later (e.g., large XML prologs). Run on a background thread to avoid UI blocking.
/// - Warning: Does not validate full SVG structure, semantics, or accessibility attributes (e.g., `aria-*`).
/// - Testing: Use `SVGConstants` to adjust `maxFileSize` or `prefixSize` in test builds for edge cases.
extension Data {
    func isSVGData() throws -> Bool {
        // Handle empty data
        guard !isEmpty else {
            return false
        }

        // Reject files exceeding max size
        guard count <= SVGConstants.maxFileSize else {
            throw SVGDetectionError.fileTooLarge
        }

        // Convert prefix of data to string (UTF-8)
        guard let string = String(data: prefix(SVGConstants.prefixSize), encoding: .utf8) else {
            throw SVGDetectionError.invalidEncoding
        }

        // Regex validation for proper SVG opening tag
        let range = NSRange(location: 0, length: string.utf16.count)
        let match = SVGConstants.regex.firstMatch(in: string, options: [], range: range)

        return match != nil
    }
}
