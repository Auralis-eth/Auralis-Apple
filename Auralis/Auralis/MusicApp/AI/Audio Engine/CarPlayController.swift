import Foundation
import CarPlay
import SwiftUI

@MainActor
final class CarPlayController: NSObject {
    private let engine: AudioEngine
    private weak var interfaceController: CPInterfaceController?

    init(engine: AudioEngine, interfaceController: CPInterfaceController) {
        self.engine = engine
        self.interfaceController = interfaceController
    }

    func presentRoot() {
        let nowPlaying = CPNowPlayingTemplate.shared
        let browse = makeBrowseTemplate()
        let tab = CPTabBarTemplate(templates: [browse, nowPlaying])
        interfaceController?.setRootTemplate(tab, animated: true)
    }

    private func makeBrowseTemplate() -> CPListTemplate {
        let title = "Browse"
        let sections: [CPListSection] = [
            CPListSection(items: [makePlaylistsItem(), makeAllMusicItem()]),
            CPListSection(items: [makeShuffleToggleItem(), makeRepeatModeItem()])
        ]
        let template = CPListTemplate(title: title, sections: sections)
        return template
    }

    private func makePlaylistsItem() -> CPListItem {
        let item = CPListItem(text: "Queues", detailText: "Next / Previous")
        item.handler = { [weak self] _, completion in
            self?.showQueues()
            completion()
        }
        return item
    }

    private func makeAllMusicItem() -> CPListItem {
        let item = CPListItem(text: "All Music NFTs", detailText: "Library")
        item.handler = { [weak self] _, completion in
            self?.showAllMusic()
            completion()
        }
        return item
    }

    private func makeShuffleToggleItem() -> CPListItem {
        let state = engine.isShuffleEnabled ? "On" : "Off"
        let item = CPListItem(text: "Shuffle", detailText: state)
        item.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            self.engine.isShuffleEnabled.toggle()
            self.refreshRoot()
            completion()
        }
        return item
    }

    private func makeRepeatModeItem() -> CPListItem {
        let modeName: String
        switch engine.repeatMode {
        case .none: modeName = "None"
        case .track: modeName = "Track"
        case .playlist: modeName = "Playlist"
        }
        let item = CPListItem(text: "Repeat", detailText: modeName)
        item.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            // Cycle repeat mode
            let nextMode: AudioEngine.RepeatMode
            switch self.engine.repeatMode {
            case .none: nextMode = .playlist
            case .playlist: nextMode = .track
            case .track: nextMode = .none
            }
            self.engine.repeatMode = nextMode
            self.refreshRoot()
            completion()
        }
        return item
    }

    private func refreshRoot() {
        // Rebuild the root to reflect toggles
        presentRoot()
    }

    private func showQueues() {
        let nextItems = engine.nextAudio.tracks.map { nft -> CPListItem in
            let title = nft.name ?? "Unknown"
            let detail = nft.artistName ?? ""
            let item = CPListItem(text: title, detailText: detail)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    try? await self?.engine.loadAndPlay(nft: nft)
                    completion()
                }
            }
            return item
        }
        let prevItems = engine.previousAudio.tracks.map { nft -> CPListItem in
            let title = nft.name ?? "Unknown"
            let detail = nft.artistName ?? ""
            let item = CPListItem(text: title, detailText: detail)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    try? await self?.engine.loadAndPlay(nft: nft)
                    completion()
                }
            }
            return item
        }

        let template = CPListTemplate(
            title: "Queues",
            sections: [
                CPListSection(items: nextItems, header: "Next Queue", sectionIndexTitle: nil),
                CPListSection(items: prevItems, header: "Previous History", sectionIndexTitle: nil)
            ]
        )
        interfaceController?.pushTemplate(template, animated: true)
    }

    private func showAllMusic() {
        // Minimal placeholder: show Next Queue as library proxy; real app can query SwiftData
        showQueues()
    }
}
