import Foundation
import Testing
import SwiftData
@testable import Auralis

@Suite("LibraryPlaylist CRUD & Query")
struct LibraryPlaylistTests {
    private func makeContainer(inMemory: Bool = true) throws -> ModelContainer {
        let schema = Schema([Playlist.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("create with defaults and persist")
    @MainActor
    func testCreateAndPersist() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pl = try context.createPlaylist(title: "Favorites")
        #expect(pl.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(pl.title == "Favorites")
        #expect(pl.tracks.isEmpty)
        #expect(pl.itemCount == 0)
        #expect(pl.createdAt.timeIntervalSince1970 > 0)
        #expect(pl.updatedAt.timeIntervalSince1970 > 0)

        // Fetch back
        let fetched = try fetchAllPlaylists(context)
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Favorites")
    }

    @Test("update fields and auto-updatedAt")
    @MainActor
    func testUpdate() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pl = try context.createPlaylist(title: "Road Trip", description: nil, imageRef: nil, tracks: [NFTExamples.musicNFT])    
        let initialUpdatedAt = pl.updatedAt
        try context.updatePlaylist(pl, title: "Road Trip 2025", items: [NFTExamples.musicNFT, NFTExamples.musicNFT2])        
        #expect(pl.title == "Road Trip 2025")
        #expect(pl.itemCount == 2)
        #expect(pl.updatedAt >= initialUpdatedAt)
    }

    @Test("search with #Predicate")
    @MainActor
    func testSearch() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        _ = try ctx.createPlaylist(title: "Chill", description: "Lo-fi", imageRef: nil)
        _ = try ctx.createPlaylist(title: "Workout", description: "HIIT", imageRef: nil)
        _ = try ctx.createPlaylist(title: "Coding", description: "Focus", imageRef: nil)

        let all = try fetchAllPlaylists(ctx)
        #expect(all.count == 3)

        let results1 = try searchPlaylists(ctx, searchText: "work")
        #expect(results1.count == 1)
        #expect(results1.first?.title == "Workout")

        let results2 = try searchPlaylists(ctx, searchText: "fi")
        #expect(results2.count == 1)
        #expect(results2.first?.title == "Chill")
    }

    @Test("delete playlist")
    @MainActor
    func testDelete() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let pl = try context.createPlaylist(title: "Temp")
        #expect(try fetchAllPlaylists(context).count == 1)
        try context.deletePlaylist(pl)
        #expect(try fetchAllPlaylists(context).isEmpty)
    }

    @Test("persistence across container recreation")
    @MainActor
    func testPersistenceAcrossRecreation() async throws {
        // Use on-disk (inMemory: false) container in a temporary directory
        let container = try makeContainer(inMemory: false)
        do {
            let ctx = ModelContext(container)
            _ = try ctx.createPlaylist(title: "KeepMe")
        }
        // Recreate container against same schema; should still fetch 1 item
        let container2 = try makeContainer(inMemory: false)
        let ctx2 = ModelContext(container2)
        let fetched = try fetchAllPlaylists(ctx2)
        #expect(fetched.count >= 1)
    }

    @Test("create with invalid empty title throws")
    @MainActor
    func testCreateInvalidEmptyTitle() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        do {
            _ = try context.createPlaylist(title: "   ")
            #expect(false, "Expected invalidData error for empty title")
        } catch let err as PlaylistError {
            switch err {
            case .invalidData:
                #expect(true)
            default:
                #expect(false, "Unexpected error: \(err)")
            }
        }
    }

    @Test("fetch all - empty, single, multiple")
    @MainActor
    func testFetchAllEmptySingleMultiple() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        // Empty
        let empty = try fetchAllPlaylists(ctx)
        #expect(empty.isEmpty)
        // Single
        _ = try ctx.createPlaylist(title: "One")
        let single = try fetchAllPlaylists(ctx)
        #expect(single.count == 1)
        // Multiple
        _ = try ctx.createPlaylist(title: "Two")
        _ = try ctx.createPlaylist(title: "Three")
        let multiple = try fetchAllPlaylists(ctx)
        #expect(multiple.count == 3)
    }

    @Test("fetch by id - found and not found")
    @MainActor
    func testFetchByID() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let created = try ctx.createPlaylist(title: "ByID")
        let found = try fetchPlaylist(ctx, by: created.id)
        #expect(found?.id == created.id)
        let missing = try fetchPlaylist(ctx, by: UUID())
        #expect(missing == nil)
    }

    @Test("update properties - title, description, image, tracks")
    @MainActor
    func testUpdateProperties() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        var tracks: [NFT] = [NFTExamples.musicNFT]
        let pl = try ctx.createPlaylist(title: "Original", description: nil, imageRef: nil, tracks: tracks)
        let initialUpdatedAt = pl.updatedAt
        try ctx.updatePlaylist(pl, title: "Updated", description: "Desc", imageRef: "img://ref", items: [NFTExamples.musicNFT2])
        #expect(pl.title == "Updated")
        #expect(pl.descriptionText == "Desc")
        #expect(pl.imageRef == "img://ref")
        #expect(pl.tracks.count == 1)
        #expect(pl.itemCount == 1)
        #expect(pl.updatedAt >= initialUpdatedAt)
    }

    @Test("update invalid title throws")
    @MainActor
    func testUpdateInvalidTitle() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let pl = try ctx.createPlaylist(title: "Valid")
        do {
            try ctx.updatePlaylist(pl, title: "   ")
            #expect(false, "Expected invalidData for whitespace title")
        } catch let err as PlaylistError {
            switch err {
            case .invalidData:
                #expect(true)
            default:
                #expect(false, "Unexpected error: \(err)")
            }
        }
    }

    @Test("delete by id - not found error")
    @MainActor
    func testDeleteByIDNotFound() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        do {
            try deletePlaylist(ctx, by: UUID())
            #expect(false, "Expected notFound error")
        } catch let err as PlaylistError {
            switch err {
            case .notFound:
                #expect(true)
            default:
                #expect(false, "Unexpected error: \(err)")
            }
        }
    }

    @Test("concurrent create and update operations are serialized safely")
    @MainActor
    func testConcurrentOperations() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        // Launch several creates concurrently (they will serialize on @MainActor)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await MainActor.run {
                        do { _ = try ctx.createPlaylist(title: "P\(i)") } catch { }
                    }
                }
            }
        }
        var all = try fetchAllPlaylists(ctx)
        #expect(all.count == 10)
        // Concurrent updates on first 5
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                if i < all.count {
                    let pl = all[i]
                    group.addTask {
                        await MainActor.run {
                            do { try ctx.updatePlaylist(pl, title: pl.title + "*") } catch { }
                        }
                    }
                }
            }
        }
        all = try fetchAllPlaylists(ctx)
        let updatedCount = all.filter { $0.title.hasSuffix("*") }.count
        #expect(updatedCount == 5)
    }

    @Test("error handling: create/update/delete invalid paths")
    @MainActor
    func testErrorHandlingCRUD() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        // Create invalid
        do {
            _ = try ctx.createPlaylist(title: "\n\t   ")
            #expect(false, "Expected invalidData on create")
        } catch let err as PlaylistError {
            if case .invalidData = err { #expect(true) } else { #expect(false, "Unexpected error: \(err)") }
        }
        // Update invalid
        let pl = try ctx.createPlaylist(title: "OK")
        do {
            try ctx.updatePlaylist(pl, title: "\t ")
            #expect(false, "Expected invalidData on update")
        } catch let err as PlaylistError {
            if case .invalidData = err { #expect(true) } else { #expect(false, "Unexpected error: \(err)") }
        }
        // Delete not found
        do {
            try deletePlaylist(ctx, by: UUID())
            #expect(false, "Expected notFound on delete by id")
        } catch let err as PlaylistError {
            if case .notFound = err { #expect(true) } else { #expect(false, "Unexpected error: \(err)") }
        }
    }
}
