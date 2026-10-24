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
        return group.options.enumerated().map { index, option in
            SubtitleTrack(
                id: subtitleTrackID(for: option, index: index),
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

        let option = group.options.enumerated().first { index, option in
            subtitleTrackID(for: option, index: index) == track.id
        }
        item.select(option?.element, in: group)
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
            .enumerated()
            .filter { _, option in option.hasMediaCharacteristic(.describesVideoForAccessibility) }
            .map { index, option in
                AudioDescriptionTrack(
                    id: subtitleTrackID(for: option, index: index),
                    displayName: option.displayName,
                    languageCode: option.locale?.language.languageCode?.identifier
                )
            }
    }
}

private func subtitleTrackID(for option: AVMediaSelectionOption, index: Int) -> String {
    [
        String(index),
        option.displayName,
        option.locale?.identifier ?? "und",
    ].joined(separator: "|")
}
