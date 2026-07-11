import AVFoundation
import Foundation

public protocol AudioTrackSource: Sendable {
    var fileURL: URL { get }
    var declaredFormat: String? { get }
    var frameLength: AVAudioFramePositionValue { get }
    var sampleRate: Double { get }

    func openAudioFile() throws -> AVAudioFile
}

public struct NativeAudioTrackSource: AudioTrackSource, Equatable {
    public let fileURL: URL
    public let declaredFormat: String?
    public let frameLength: AVAudioFramePositionValue
    public let sampleRate: Double

    public init(fileURL: URL, declaredFormat: String? = nil) throws {
        self.fileURL = fileURL
        self.declaredFormat = declaredFormat

        do {
            let file = try AVAudioFile(forReading: fileURL)
            self.frameLength = file.length
            self.sampleRate = file.fileFormat.sampleRate
        } catch {
            throw AuraPlayError.corruptedFile(fileURL)
        }
    }

    public func openAudioFile() throws -> AVAudioFile {
        do {
            return try AVAudioFile(forReading: fileURL)
        } catch {
            throw AuraPlayError.corruptedFile(fileURL)
        }
    }
}

public protocol DecoderPlugin: Sendable {
    var supportedExtensions: Set<String> { get }
    func makeSource(for fileURL: URL, declaredFormat: String?) throws -> any AudioTrackSource
}

public struct AudioTrackSourceFactory: Sendable {
    public static let nativeExtensions: Set<String> = ["mp3", "m4a", "caf", "wav", "aif", "aiff", "flac"]
    public static let deferredExtensions: Set<String> = ["ogg", "opus"]

    private let plugins: [any DecoderPlugin]

    public init(plugins: [any DecoderPlugin] = []) {
        self.plugins = plugins
    }

    public func makeSource(for fileURL: URL, declaredFormat: String? = nil) throws -> any AudioTrackSource {
        let mediaExtension = normalizedExtension(fileURL: fileURL, declaredFormat: declaredFormat)

        if Self.nativeExtensions.contains(mediaExtension) {
            return try NativeAudioTrackSource(fileURL: fileURL, declaredFormat: declaredFormat)
        }

        if let plugin = plugins.first(where: { $0.supportedExtensions.contains(mediaExtension) }) {
            return try plugin.makeSource(for: fileURL, declaredFormat: declaredFormat)
        }

        throw AuraPlayError.unsupportedFormat(mediaExtension.isEmpty ? declaredFormat : mediaExtension)
    }

    private func normalizedExtension(fileURL: URL, declaredFormat: String?) -> String {
        if let declared = declaredFormat?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !declared.isEmpty {
            return declared.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }

        return fileURL.pathExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
