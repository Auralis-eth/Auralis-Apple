import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

public struct VideoPresentationAnalyzer: Sendable {
    private let landscapeThreshold: Double
    private let squareTolerance: Double

    public init(landscapeThreshold: Double = 1.2, squareTolerance: Double = 0.05) {
        self.landscapeThreshold = landscapeThreshold
        self.squareTolerance = squareTolerance
    }

    public func analyze(asset: AVAsset) async throws -> VideoPresentationInfo {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return VideoPresentationInfo(aspectRatio: 1, isLandscape: false, isSquare: true)
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        return analyze(naturalSize: naturalSize, preferredTransform: preferredTransform)
    }

    public func analyze(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> VideoPresentationInfo {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let correctedSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let width = max(correctedSize.width, 1)
        let height = max(correctedSize.height, 1)
        let ratio = Double(width / height)
        let isSquare = abs(ratio - 1) <= squareTolerance

        return VideoPresentationInfo(
            aspectRatio: ratio,
            isLandscape: ratio > landscapeThreshold,
            isSquare: isSquare
        )
    }
}

public struct HDRDetector: Sendable {
    public init() {}

    public func isHDR(asset: AVAsset) async throws -> Bool {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return false }
        let characteristics = try await track.load(.mediaCharacteristics)
        if characteristics.contains(.containsHDRVideo) {
            return true
        }

        let formatDescriptions = try await track.load(.formatDescriptions)
        return isHDR(formatDescriptions: formatDescriptions)
    }

    public func isHDR(formatDescriptions: [CMFormatDescription]) -> Bool {
        formatDescriptions.contains { formatDescription in
            guard let extensions = CMFormatDescriptionGetExtensions(formatDescription) as NSDictionary? else {
                return false
            }

            let primaries = metadataString(
                extensions[kCMFormatDescriptionExtension_ColorPrimaries]
                    ?? extensions[kCVImageBufferColorPrimariesKey]
            )
            let transferFunction = metadataString(
                extensions[kCMFormatDescriptionExtension_TransferFunction]
                    ?? extensions[kCVImageBufferTransferFunctionKey]
            )

            let hasWideColorPrimaries = primaries.contains("2020") || primaries.contains("p3")
            let hasHDRTransfer = transferFunction.contains("2084")
                || transferFunction.contains("pq")
                || transferFunction.contains("hlg")
                || transferFunction.contains("2100")

            return hasWideColorPrimaries && hasHDRTransfer
        }
    }

    public func shouldShowHDRBadge(isHDRContent: Bool, deviceSupportsHDR: Bool) -> Bool {
        isHDRContent && deviceSupportsHDR
    }

    private func metadataString(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String {
            return string.lowercased()
        }
        return String(describing: value).lowercased()
    }
}

public struct PosterFrameGenerator: Sendable {
    public init() {}

    public func poster(for asset: AVAsset, at seconds: Double = 1.0, maximumWidth: CGFloat = 600) async -> PlatformImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumWidth, height: 0)

        do {
            let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
            #if canImport(UIKit)
            return PlatformImage(cgImage: result.image)
            #elseif canImport(AppKit)
            return PlatformImage(cgImage: result.image, size: .zero)
            #else
            return nil
            #endif
        } catch {
            return nil
        }
    }
}

public struct CachedPosterFrameGenerator: Sendable {
    private let generator: PosterFrameGenerator
    private let cache: any VideoArtworkCaching

    public init(generator: PosterFrameGenerator = PosterFrameGenerator(), cache: any VideoArtworkCaching) {
        self.generator = generator
        self.cache = cache
    }

    public func poster(
        for asset: AVAsset,
        mediaID: String,
        at seconds: Double = 1.0,
        maximumWidth: CGFloat = 600
    ) async -> PlatformImage? {
        if let cached = await cache.cachedPoster(for: mediaID) {
            return cached
        }

        guard let poster = await generator.poster(for: asset, at: seconds, maximumWidth: maximumWidth) else {
            return nil
        }
        await cache.storePoster(poster, for: mediaID)
        return poster
    }
}
