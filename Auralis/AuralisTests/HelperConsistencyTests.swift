import SwiftData
import SwiftUI
import Testing
@testable import Auralis

@Suite
struct HelperConsistencyTests {
    @Test("8 character hex values resolve consistently across helper paths")
    func hexHelpersUseSharedRGBAConvention() {
        let fromColorInit = Color(hexString: "11223344")
        let fromStringHelper = "11223344".toColor()

        #expect(rgbaComponents(fromColorInit) == rgbaComponents(fromStringHelper))
    }

    @Test("Solana formatted chain IDs use the Solana label")
    func solanaFormattedChainIDUsesExpectedLabel() {
        #expect(Chain.solanaMainnet.formattedChainId == "Solana Network")
        #expect(Chain.solanaDevnetTestnet.formattedChainId == "Solana Network")
    }

    @Test("playlist creation persists the trimmed title")
    @MainActor
    func playlistCreationPersistsTrimmedTitle() throws {
        let container = try makePlaylistContainer()
        let context = ModelContext(container)

        let playlist = try context.createPlaylist(title: "  Chill Mix  ")

        #expect(playlist.title == "Chill Mix")
    }

    @MainActor
    private func makePlaylistContainer() throws -> ModelContainer {
        let schema = Schema([Playlist.self, NFT.self, Tag.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func rgbaComponents(_ color: Color) -> [CGFloat] {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
        #else
        return []
        #endif
    }
}
