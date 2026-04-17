//
//  NFTImageView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import ImageIO
import SwiftUI

// Image Cache Manager
class ImageCache {
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
class ImageLoader: ObservableObject {
    private static let maxPixelDimension = 1_024

    enum LoadingError: Error {
        case invalidData
        case networkError
        case svgData
        case videoData
        case unsupportedURL
    }
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var error: LoadingError?

    private var loadingTask: Task<Void, Never>?
    private let url: URL
    private let cacheKey: String

    init(url: URL) {
        self.url = url
        self.cacheKey = url.absoluteString

        // Check cache first
        if let cachedImage = ImageCache.shared.get(for: cacheKey) {
            self.image = cachedImage
            return
        }

        loadImage()
    }

    private func loadImage() {
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

        loadingTask = Task { @MainActor in
            defer {
                isLoading = false
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse,
                   let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    let content = contentType.lowercased()
                    if content.contains("video/mp4") || contentType.contains("video/mpeg4") {
                        error = .videoData
                        return
                    }
                }

                guard !Task.isCancelled else { return }

                if let downloadedImage = Self.downsampledImage(from: data, maxPixelDimension: Self.maxPixelDimension) {
                    ImageCache.shared.set(downloadedImage, for: cacheKey)
                    image = downloadedImage
                } else if (try? data.isSVGData()) == true {
                    error = .svgData
                } else {
                    error = .invalidData
                }
            } catch let loadingError {
                if !Task.isCancelled {
                    _ = loadingError
                    error = .networkError
                }
            }
        }
    }

    func cancel() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    private static func downsampledImage(from data: Data, maxPixelDimension: Int) -> UIImage? {
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
}

// Cached async image view
struct CachedAsyncImage: View {
    @StateObject private var loader: ImageLoader

    init(url: URL) {
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
//                        switch error {
//                            case .invalidData:
//                                SystemImage("camera.macro.slash")
//                            case .networkError:
//                                SystemImage("network.slash")
//                        }
//                        SecondaryCaptionFontText(error == .invalidData ? "Invalid Image" : "Network Error")
                        SecondaryText("\(error as NSError).code)")
                        SecondaryText(error.localizedDescription)
                    }
                    .foregroundStyle(Color.error)
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
