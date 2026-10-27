import Foundation

public struct MetadataParser: MetadataParsing {
    public init() {}

    public func parse(json: String) -> MetadataParsed {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return MetadataParsed(schemaVersion: .unknown, rawJSON: json)
        }

        // Helius DAS assets nest everything under `content`; check this first
        // because the shape is specific and would otherwise fall through every
        // root-level detector and be classified as `.unknown` / unplayable.
        if detectsHeliusDAS(dictionary) {
            return parseHeliusDAS(dictionary, rawJSON: json)
        }
        if detectsSoundXyz(dictionary) {
            return parseSoundXyz(dictionary, rawJSON: json)
        }
        if detectsZora(dictionary) {
            return parseZora(dictionary, rawJSON: json)
        }
        if detectsMetaplex(dictionary) {
            return parseMetaplex(dictionary, rawJSON: json)
        }
        if detectsERC1155(dictionary) {
            return parseERC1155(dictionary, rawJSON: json)
        }
        if detectsOpenSea(dictionary) {
            return parseOpenSea(dictionary, rawJSON: json)
        }

        return MetadataParsed(schemaVersion: .unknown, rawJSON: json)
    }
}

private extension MetadataParser {
    func detectsHeliusDAS(_ metadata: [String: Any]) -> Bool {
        guard let content = dictionary(metadata["content"]) else {
            return false
        }
        let hasDASMarkers = metadata["interface"] != nil
            || metadata["ownership"] != nil
            || content["json_uri"] != nil
        let hasContentShape = content["metadata"] != nil
            || content["links"] != nil
            || content["files"] != nil
        return hasDASMarkers && hasContentShape
    }

    // Normalizes a Helius DAS asset into the shared metadata shape. Media lives
    // under `content.links.audio_url` / `content.links.animation_url` and
    // `content.files[]` (uri/cdn_uri + mime), none of which the root-level
    // detectors above can see.
    func parseHeliusDAS(_ metadata: [String: Any], rawJSON: String) -> MetadataParsed {
        let content = dictionary(metadata["content"]) ?? [:]
        let contentMetadata = dictionary(content["metadata"]) ?? [:]
        let links = dictionary(content["links"]) ?? [:]
        let scannedFiles = mediaFiles(from: content["files"])
        let creators = files(in: metadata["creators"])

        return MetadataParsed(
            name: string(contentMetadata["name"]),
            description: string(contentMetadata["description"]),
            creatorName: string(contentMetadata["artist"])
                ?? creators?.first.flatMap { string($0["address"]) },
            collectionName: nil,
            artworkURL: string(links["image"]),
            audioURL: string(links["audio_url"]) ?? scannedFiles.audioURL,
            videoURL: scannedFiles.videoURL ?? string(links["animation_url"]),
            duration: double(contentMetadata["duration"]),
            format: scannedFiles.format,
            attributes: attributes(from: contentMetadata["attributes"]),
            schemaVersion: .heliusDAS,
            rawJSON: rawJSON
        )
    }

    func detectsSoundXyz(_ metadata: [String: Any]) -> Bool {
        string(metadata["losslessAudio"]) != nil ||
        string(metadata["audio"]) != nil ||
        string(metadata["artist"]) != nil
    }

    func detectsZora(_ metadata: [String: Any]) -> Bool {
        if dictionary(metadata["content"])?["mime"] != nil {
            return true
        }
        return metadata["zora_metadata"] != nil
    }

    func detectsMetaplex(_ metadata: [String: Any]) -> Bool {
        metadata["symbol"] != nil ||
        metadata["seller_fee_basis_points"] != nil ||
        files(in: dictionary(metadata["properties"])?["creators"]) != nil
    }

    func detectsERC1155(_ metadata: [String: Any]) -> Bool {
        files(in: dictionary(metadata["properties"])?["files"]) != nil
    }

    func detectsOpenSea(_ metadata: [String: Any]) -> Bool {
        string(metadata["name"]) != nil || string(metadata["image"]) != nil
    }

    func parseSoundXyz(_ metadata: [String: Any], rawJSON: String) -> MetadataParsed {
        MetadataParsed(
            name: string(metadata["name"]),
            description: string(metadata["description"]),
            creatorName: string(metadata["artist"]),
            collectionName: string(metadata["project"]),
            artworkURL: string(metadata["image"]),
            audioURL: string(metadata["losslessAudio"]) ?? string(metadata["audio"]),
            videoURL: string(metadata["animation_url"]),
            duration: double(metadata["duration"]),
            format: nil,
            attributes: soundAttributes(metadata),
            schemaVersion: .soundXyz,
            rawJSON: rawJSON
        )
    }

    func parseZora(_ metadata: [String: Any], rawJSON: String) -> MetadataParsed {
        let content = dictionary(metadata["content"])
        let mime = string(content?["mime"])
        let uri = string(content?["uri"])
        let format = formatFromMIME(mime)
        let isAudio = mime?.lowercased().hasPrefix("audio/") == true
        let isVideo = mime?.lowercased().hasPrefix("video/") == true

        return MetadataParsed(
            name: string(metadata["name"]),
            description: string(metadata["description"]),
            creatorName: nil,
            collectionName: nil,
            artworkURL: string(metadata["image"]),
            audioURL: isAudio ? uri : nil,
            videoURL: isVideo ? uri : nil,
            duration: double(metadata["duration"]),
            format: format,
            attributes: attributes(from: metadata["attributes"]),
            schemaVersion: .zora,
            rawJSON: rawJSON
        )
    }

    func parseMetaplex(_ metadata: [String: Any], rawJSON: String) -> MetadataParsed {
        let properties = dictionary(metadata["properties"])
        let scannedFiles = mediaFiles(from: properties?["files"])
        let creators = files(in: properties?["creators"])
        let firstCreator = creators?.first.flatMap { string($0["address"]) }
        let collection = dictionary(metadata["collection"])

        return MetadataParsed(
            name: string(metadata["name"]),
            description: string(metadata["description"]),
            creatorName: firstCreator,
            collectionName: string(collection?["name"]),
            artworkURL: string(metadata["image"]),
            audioURL: scannedFiles.audioURL,
            videoURL: scannedFiles.videoURL ?? string(metadata["animation_url"]),
            duration: double(metadata["duration"]),
            format: scannedFiles.format,
            attributes: attributes(from: metadata["attributes"]),
            schemaVersion: .metaplex,
            rawJSON: rawJSON
        )
    }

    func parseERC1155(_ metadata: [String: Any], rawJSON: String) -> MetadataParsed {
        let properties = dictionary(metadata["properties"])
        let scannedFiles = mediaFiles(from: properties?["files"])

        return MetadataParsed(
            name: string(metadata["name"]),
            description: string(metadata["description"]),
            creatorName: string(properties?["creator"]),
            collectionName: nil,
            artworkURL: string(metadata["image"]),
            audioURL: scannedFiles.audioURL,
            videoURL: scannedFiles.videoURL,
            duration: double(metadata["duration"]),
            format: scannedFiles.format,
            attributes: attributes(from: metadata["attributes"]),
            schemaVersion: .erc1155,
            rawJSON: rawJSON
        )
    }

    func parseOpenSea(_ metadata: [String: Any], rawJSON: String) -> MetadataParsed {
        let properties = dictionary(metadata["properties"])

        return MetadataParsed(
            name: string(metadata["name"]),
            description: string(metadata["description"]),
            creatorName: string(properties?["creator"]),
            collectionName: nil,
            artworkURL: string(metadata["image"]),
            audioURL: string(properties?["audio_url"]),
            videoURL: string(metadata["animation_url"]),
            duration: double(metadata["duration"]),
            format: nil,
            attributes: attributes(from: metadata["attributes"]),
            schemaVersion: .openSea,
            rawJSON: rawJSON
        )
    }

    func mediaFiles(from value: Any?) -> (audioURL: String?, videoURL: String?, format: String?) {
        let fileList = files(in: value) ?? []
        var audioURL: String?
        var videoURL: String?
        var format: String?

        for file in fileList {
            let mime = string(file["type"]) ?? string(file["mime"])
            let lowercasedMIME = mime?.lowercased()
            let uri = string(file["uri"]) ?? string(file["cdn_uri"])

            if audioURL == nil, lowercasedMIME?.hasPrefix("audio/") == true {
                audioURL = uri
                format = format ?? formatFromMIME(mime)
            }

            if videoURL == nil, lowercasedMIME?.hasPrefix("video/") == true {
                videoURL = uri
                format = format ?? formatFromMIME(mime)
            }
        }

        return (audioURL, videoURL, format)
    }

    func attributes(from value: Any?) -> [String: String] {
        guard let attributeList = files(in: value) else {
            return [:]
        }

        var flattened: [String: String] = [:]
        for attribute in attributeList {
            guard let key = string(attribute["trait_type"]) else {
                continue
            }
            if let value = string(attribute["value"]) {
                flattened[key] = value
            } else if let value = attribute["value"] {
                flattened[key] = String(describing: value)
            }
        }
        return flattened
    }

    func soundAttributes(_ metadata: [String: Any]) -> [String: String] {
        var flattened = attributes(from: metadata["attributes"])
        if let trackNumber = string(metadata["trackNumber"]) ?? metadata["trackNumber"].map(String.init(describing:)) {
            flattened["trackNumber"] = trackNumber
        }
        if let version = string(metadata["version"]) {
            flattened["version"] = version
        }
        return flattened
    }

    func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    func double(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = string(value) {
            return Double(string)
        }
        return nil
    }

    func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    func files(in value: Any?) -> [[String: Any]]? {
        value as? [[String: Any]]
    }

    func formatFromMIME(_ mime: String?) -> String? {
        switch mime?.lowercased() {
        case "audio/mpeg", "audio/mp3":
            return "mp3"
        case "audio/flac", "audio/x-flac":
            return "flac"
        case "audio/mp4", "audio/x-m4a":
            return "m4a"
        case "audio/wav", "audio/x-wav":
            return "wav"
        case "audio/aiff", "audio/x-aiff":
            return "aiff"
        case "audio/ogg":
            return "ogg"
        case "audio/opus":
            return "opus"
        case "video/mp4":
            return "mp4"
        case "video/quicktime":
            return "mov"
        case "video/webm":
            return "webm"
        default:
            return nil
        }
    }
}
