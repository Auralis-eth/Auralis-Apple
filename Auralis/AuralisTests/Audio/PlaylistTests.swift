//import Foundation
//import Testing
//import SwiftData
//@testable import Auralis
//
//@Suite("Playlist model basics")
//struct PlaylistTests {
//    private func makeContainer() throws -> ModelContainer {
//        let schema = Schema([Playlist.self, NFT.self])
//        let config = ModelConfiguration(isStoredInMemoryOnly: true)
//        return try ModelContainer(for: schema, configurations: [config])
//    }
//
//    @Test("create, mutate, and fetch playlist")
//    @MainActor
//    func testCreateAndFetch() async throws {
//        let container = try makeContainer()
//        let context = ModelContext(container)
//
//        let pl = Playlist(name: "Favorites")
//        #expect(pl.name == "Favorites")
//        #expect(pl.tracks.isEmpty)
//        #expect(pl.dateCreated.timeIntervalSince1970 > 0)
//        context.insert(pl)
//        try context.save()
//
//        // Append two NFTs
//        let n1 = NFTExamples.musicNFT
//        let n2 = NFTExamples.musicNFT2
//        pl.tracks.append(n1)
//        pl.tracks.append(n2)
//        try context.save()
//
//        // Fetch back
//        let fetch = FetchDescriptor<Playlist>(predicate: #Predicate { $0.name == "Favorites" })
//        let fetched = try context.fetch(fetch)
//        #expect(fetched.count == 1)
//        if let got = fetched.first {
//            #expect(got.tracks.count == 2)
//            #expect(got.tracks.first?.id == n1.id)
//            #expect(got.tracks.last?.id == n2.id)
//            #expect(got.name == "Favorites")
//            #expect(got.dateCreated.timeIntervalSince1970 > 0)
//        }
//    }
//}
