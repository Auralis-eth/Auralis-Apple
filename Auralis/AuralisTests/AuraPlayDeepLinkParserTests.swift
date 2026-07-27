import AuralisPrimaryModels
import AuralisShellCore
@testable import Auralis
import Foundation
import MusicFeature
import Testing

struct AuraPlayDeepLinkParserTests {
    @Test("auraplay playlist links parse into music playlist destination")
    func parsesPlaylistLink() throws {
        let parser = AppDeepLinkParser()
        let url = try #require(URL(string: "auraplay://playlist/playlist-1"))

        let result = parser.parse(url: url)

        guard case .success(.destination(.auraPlayPlaylist(id: "playlist-1"))) = result else {
            Issue.record("Unexpected parser result: \(String(describing: result))")
            return
        }
    }

    @Test("auraplay collection links preserve chain disambiguation")
    func parsesCollectionLink() throws {
        let parser = AppDeepLinkParser()
        let url = try #require(URL(string: "auraplay://collection/0xabc?chain=base-mainnet"))

        let result = parser.parse(url: url)

        guard case .success(.destination(.auraPlayCollection(identifier: "0xabc", chain: .baseMainnet))) = result else {
            Issue.record("Unexpected parser result: \(String(describing: result))")
            return
        }
    }

    @Test("auraplay creator links parse into creator destination")
    func parsesCreatorLink() throws {
        let parser = AppDeepLinkParser()
        let url = try #require(URL(string: "auraplay://creator/creator%3Across"))

        let result = parser.parse(url: url)

        guard case .success(.destination(.auraPlayCreator(identifier: "creator:cross"))) = result else {
            Issue.record("Unexpected parser result: \(String(describing: result))")
            return
        }
    }

    @MainActor
    @Test("collection share URL round trips into AuraPlay media-store collection route")
    func collectionShareURLRoundTripsIntoMediaStoreRoute() throws {
        let group = LibraryCollectionGroup(
            id: "base-mainnet|0xabc",
            collectionName: "Waves",
            contractAddress: "0xabc",
            chain: .baseMainnet,
            itemCount: 2,
            artworkURLStrings: []
        )
        let shareURL = try #require(AuraPlaySharePolicy().collectionShareRequest(group: group).url)
        let result = AppDeepLinkParser().parse(url: shareURL)
        let router = AppRouter()

        guard case .success(.destination(.auraPlayCollection(let identifier, let chain))) = result else {
            Issue.record("Unexpected parser result: \(String(describing: result))")
            return
        }

        router.showMusicCollectionDetail(
            key: "\(try #require(chain).rawValue)|\(identifier)",
            title: "Collection"
        )

        #expect(shareURL.absoluteString == "auraplay://collection/0xabc?chain=base-mainnet")
        #expect(router.musicPath == [.collection(key: "base-mainnet|0xabc", title: "Collection")])
    }
}
