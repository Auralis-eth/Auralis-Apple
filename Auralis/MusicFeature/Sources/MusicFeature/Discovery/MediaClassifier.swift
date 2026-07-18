import Foundation

public struct MediaClassifier: MediaClassifying {
    public typealias Clock = @Sendable () -> Date

    private let urlResolver: URLResolver
    private let clock: Clock

    public init(
        urlResolver: URLResolver = URLResolver(),
        clock: @escaping Clock = Date.init
    ) {
        self.urlResolver = urlResolver
        self.clock = clock
    }

    public func classify(parsed: MetadataParsed, token: NFTTokenDTO) -> MediaItemDTO {
        let artworkURL = parsed.artworkURL.flatMap { urlResolver.resolve($0)?.absoluteString }
        var resolvedAudioURL = parsed.audioURL.flatMap { urlResolver.resolve($0)?.absoluteString }
        var resolvedVideoURL = parsed.videoURL.flatMap { urlResolver.resolve($0)?.absoluteString }
        var format = parsed.format ?? detectedFormat(audioURL: resolvedAudioURL, videoURL: resolvedVideoURL)

        if resolvedAudioURL == nil,
           let videoURL = resolvedVideoURL,
           shouldTreatAnimationURLAsAudio(videoURL, format: format) {
            resolvedAudioURL = videoURL
            resolvedVideoURL = nil
            format = format ?? detectedFormat(audioURL: resolvedAudioURL, videoURL: nil)
        }

        if format == nil, resolvedVideoURL != nil {
            format = "mp4"
        }

        let hasVideo = resolvedVideoURL != nil && Self.videoFormats.contains(format ?? "")
        let hasAudio = resolvedAudioURL != nil || (resolvedVideoURL != nil && Self.audioFormats.contains(format ?? ""))
        let now = clock()

        return MediaItemDTO(
            id: token.compositeID,
            nftTokenId: token.compositeID,
            title: parsed.name ?? token.name ?? "Untitled #\(token.tokenId)",
            creatorName: parsed.creatorName,
            collectionName: parsed.collectionName ?? token.collectionName,
            artworkURL: artworkURL,
            audioURL: resolvedAudioURL,
            videoURL: resolvedVideoURL,
            durationSeconds: parsed.duration,
            format: format,
            hasAudio: hasAudio,
            hasVideo: hasVideo,
            isPlayable: hasAudio || hasVideo,
            chain: token.chain,
            contractAddress: token.contractAddress,
            tokenId: token.tokenId,
            tokenStandard: token.tokenStandard,
            walletAddress: token.walletAddress,
            classifiedAt: now,
            createdAt: now
        )
    }
}

public extension MediaItemDTO {
    func makeAuraPlayMediaItemUpsertRequest() -> AuraPlayMediaItemUpsertRequest {
        AuraPlayMediaItemUpsertRequest(
            sourceNFTID: nftTokenId,
            accountAddressRawValue: walletAddress,
            chain: chain,
            contractAddressRawValue: contractAddress,
            tokenID: tokenId,
            tokenType: tokenStandard,
            title: title,
            artistName: creatorName,
            creatorIdentifierRawValue: contractAddress ?? creatorName,
            collectionName: collectionName,
            normalizedTitleKey: Self.normalizedKey(title),
            normalizedArtistKey: Self.normalizedKey(creatorName),
            normalizedCollectionKey: Self.normalizedKey(collectionName),
            artworkURLString: artworkURL,
            playbackURLString: audioURL ?? videoURL,
            durationSeconds: durationSeconds,
            contentType: format,
            sourceUpdatedAtRawValue: nil,
            hasArtwork: artworkURL != nil,
            hasAudio: hasAudio,
            hasVideo: hasVideo,
            isPlayable: isPlayable,
            isSearchable: true
        )
    }

    private static func normalizedKey(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

private extension MediaClassifier {
    static let audioFormats: Set<String> = ["mp3", "flac", "m4a", "wav", "aiff", "ogg", "opus"]
    static let videoFormats: Set<String> = ["mp4", "mov", "webm"]

    func detectedFormat(audioURL: String?, videoURL: String?) -> String? {
        if let audioFormat = format(from: audioURL) {
            return audioFormat
        }
        return format(from: videoURL)
    }

    func format(from urlString: String?) -> String? {
        guard let urlString,
              let url = URL(string: urlString) else {
            return nil
        }

        switch url.pathExtension.lowercased() {
        case "mp3":
            return "mp3"
        case "flac":
            return "flac"
        case "m4a":
            return "m4a"
        case "wav":
            return "wav"
        case "aif", "aiff":
            return "aiff"
        case "ogg":
            return "ogg"
        case "opus":
            return "opus"
        case "mp4":
            return "mp4"
        case "mov":
            return "mov"
        case "webm":
            return "webm"
        default:
            return nil
        }
    }

    func shouldTreatAnimationURLAsAudio(_ urlString: String, format: String?) -> Bool {
        if Self.audioFormats.contains(format ?? "") {
            return true
        }
        if Self.videoFormats.contains(format ?? "") {
            return false
        }

        guard let url = URL(string: urlString) else {
            return false
        }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        return path.contains("audio") ||
        host.contains("sound.xyz") ||
        host.contains("catalog.works")
    }
}
