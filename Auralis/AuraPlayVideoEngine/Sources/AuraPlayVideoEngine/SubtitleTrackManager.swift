import AVFoundation
import Foundation

@MainActor
public struct SubtitleTrackManager {
    public static let preferredLanguageKey = "com.auraplay.preferredSubtitleLanguage"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var preferredLanguageCode: String? {
        userDefaults.string(forKey: Self.preferredLanguageKey)
    }

    public func availableTracks(for item: AVPlayerItem) async throws -> [SubtitleTrack] {
        guard let group = try await item.asset.loadMediaSelectionGroup(for: .legible) else { return [] }
        return group.options.map { option in
            SubtitleTrack(
                id: option.displayName + (option.locale?.identifier ?? ""),
                displayName: option.displayName,
                languageCode: option.locale?.language.languageCode?.identifier
            )
        }
    }

    public func select(track: SubtitleTrack?, on item: AVPlayerItem) async throws {
        guard let group = try await item.asset.loadMediaSelectionGroup(for: .legible) else { return }

        guard let track else {
            item.select(nil, in: group)
            return
        }

        let option = group.options.first { option in
            option.displayName == track.displayName && option.locale?.language.languageCode?.identifier == track.languageCode
        }
        item.select(option, in: group)
        if let languageCode = track.languageCode {
            userDefaults.set(languageCode, forKey: Self.preferredLanguageKey)
        }
    }

    @discardableResult
    public func autoSelectPreferredTrack(on item: AVPlayerItem) async throws -> SubtitleTrack? {
        guard let preferredLanguageCode else { return nil }
        let tracks = try await availableTracks(for: item)
        guard let preferredTrack = tracks.first(where: { $0.languageCode == preferredLanguageCode }) else {
            return nil
        }

        try await select(track: preferredTrack, on: item)
        return preferredTrack
    }

    public func availableAudioDescriptionTracks(for item: AVPlayerItem) async throws -> [AudioDescriptionTrack] {
        guard let group = try await item.asset.loadMediaSelectionGroup(for: .audible) else { return [] }

        return group.options
            .filter { $0.hasMediaCharacteristic(.describesVideoForAccessibility) }
            .map { option in
                AudioDescriptionTrack(
                    id: option.displayName + (option.locale?.identifier ?? ""),
                    displayName: option.displayName,
                    languageCode: option.locale?.language.languageCode?.identifier
                )
            }
    }
}
