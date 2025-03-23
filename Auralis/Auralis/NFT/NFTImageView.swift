//
//  NFTImageView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftUI

struct NFTImageView: View {
    var image: NFTDisplayModel.ImageSource?
    var body: some View {
        if let image {
            switch image {
                case .url(let imageURL):
                    CachedAsyncImage(url: imageURL)
                case .data(let data):
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                    }
                case .svg(let svg):
                    SVGView(string: svg)
            }
        } else {
            ZStack {
                Color.surface
                    .aspectRatio(1, contentMode: .fit)
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.textSecondary)
            }
        }
    }
}


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
class ImageLoader: ObservableObject {
    enum LoadingError: Error {
        case invalidData
        case networkError
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
        error = nil

        loadingTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                // Check if task was cancelled
                if Task.isCancelled { return }

                if let downloadedImage = UIImage(data: data) {
                    // Cache the loaded image
                    ImageCache.shared.set(downloadedImage, for: self.cacheKey)
                    await MainActor.run {
                        self.image = downloadedImage
                    }
                } else {
                    self.error = .invalidData
                }
            } catch {
                if !Task.isCancelled {
                    self.error = .networkError
                }
            }
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    func cancel() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    deinit {
        cancel()
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
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .shadow(radius: 5)
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
                        switch error {
                            case .invalidData:
                                Image(systemName: "camera.macro.slash")
                            case .networkError:
                                Image(systemName: "network.slash")
                        }
                        Text(error == .invalidData ? "Invalid Image" : "Network Error")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .foregroundColor(.error)
                }
            } else {
                ZStack {
                    Color.surface
                        .aspectRatio(1, contentMode: .fit)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }
}
