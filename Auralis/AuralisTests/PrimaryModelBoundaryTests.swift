import Foundation
import AuralisPrimaryPersistence
import MusicFeature
import ReceiptStorage
import SwiftData
import Testing
import TokenStorage

@Suite(.tags(.architecture))
struct PrimaryModelBoundaryTests {
    @Test("primary models do not import UI frameworks")
    func primaryModelsDoNotImportUIFrameworks() throws {
        let sourceFiles = try swiftFiles(in: primaryModelsSourceRoot)

        for file in sourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(source.contains("import SwiftData") == false, "\(file.path) imports SwiftData")
            #expect(source.contains("import SwiftUI") == false, "\(file.path) imports SwiftUI")
            #expect(source.contains("import UIKit") == false, "\(file.path) imports UIKit")
            #expect(source.contains("@Model") == false, "\(file.path) declares a SwiftData model")
        }
    }

    @Test("primary persistence owns the remaining primary SwiftData model cluster")
    func primaryPersistenceOwnsRemainingPrimaryModelCluster() throws {
        let pureSourceFiles = try swiftFiles(in: primaryModelsSourceRoot)
        let persistedModelNames = [
            "EOAccount",
            "NFT",
            "Tag",
            "Playlist",
            "MusicLibraryItem",
            "SearchHistoryRecord",
        ]

        for file in pureSourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for modelName in persistedModelNames {
                #expect(source.contains("final class \(modelName)") == false, "\(file.path) declares \(modelName)")
            }
        }

        let primaryPersistenceModels: [any PersistentModel.Type] = [
            EOAccount.self,
            NFT.self,
            Tag.self,
            Playlist.self,
            MusicLibraryItem.self,
            SearchHistoryRecord.self,
        ]

        #expect(primaryPersistenceModels.count == persistedModelNames.count)
    }

    @Test("storage-owned models live in storage packages")
    func storageOwnedModelsLiveInStoragePackages() throws {
        let primarySourceFiles = try swiftFiles(in: projectRoot.appendingPathComponent("AuralisPrimaryModels/Sources"))

        for file in primarySourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(source.contains("final class StoredReceipt") == false, "\(file.path) declares StoredReceipt")
            #expect(source.contains("final class TokenHolding") == false, "\(file.path) declares TokenHolding")
            #expect(source.contains("final class AuraPlayMediaItem") == false, "\(file.path) declares AuraPlayMediaItem")
        }

        let storageModels: [any PersistentModel.Type] = [
            StoredReceipt.self,
            TokenHolding.self,
        ]

        #expect(storageModels.count == 2)
        #expect(AuraPlaySchema.models.contains { $0 == AuraPlayMediaItem.self })
    }
}

private var primaryModelsSourceRoot: URL {
    projectRoot.appendingPathComponent("AuralisPrimaryModels/Sources/AuralisPrimaryModels")
}

private var projectRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func swiftFiles(in directory: URL) throws -> [URL] {
    let keys: Set<URLResourceKey> = [.isDirectoryKey]
    let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
    )

    var files: [URL] = []
    while let file = enumerator?.nextObject() as? URL {
        let values = try file.resourceValues(forKeys: keys)
        if values.isDirectory == true {
            continue
        }
        if file.pathExtension == "swift" {
            files.append(file)
        }
    }

    return files
}
