@testable import Auralis
import AuralisCrypto
import AuralisTestSupport
import Foundation
import AuralisOperators
import AuralisReceipts
import SwiftData
import Testing

@Suite(.tags(.architecture, .slow))
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
            "Playlist"
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
            Playlist.self
        ]

        #expect(primaryPersistenceModels.count == persistedModelNames.count)
    }

    @Test("storage-owned models live in storage packages")
    func storageOwnedModelsLiveInStoragePackages() throws {
        let primarySourceFiles = try swiftFiles(in: primaryModelsSourceRoot)

        for file in primarySourceFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(source.contains("final class StoredReceipt") == false, "\(file.path) declares StoredReceipt")
            #expect(source.contains("final class TokenHolding") == false, "\(file.path) declares TokenHolding")
            #expect(source.contains("final class AuraPlayMediaItem") == false, "\(file.path) declares AuraPlayMediaItem")
            #expect(source.contains("final class SearchHistoryRecord") == false, "\(file.path) declares SearchHistoryRecord")
        }

        let storageModels: [any PersistentModel.Type] = [
            StoredReceipt.self,
            TokenHolding.self,
            MusicLibraryItem.self,
            SearchHistoryRecord.self
        ]

        #expect(storageModels.count == 4)
        #expect(AuraPlaySchema.models.contains { $0 == AuraPlayMediaItem.self })
    }
}

/// The pure primary-model values, which are now a source group rather than their own package.
///
/// Scoped to the group and not to `AuralisCrypto/Sources/AuralisCrypto`: the whole crypto module
/// legitimately contains SwiftData storage, so pointing these checks at the module root would flag
/// `TokenStorage` and `PrimaryPersistence` for doing exactly what they exist to do.
private var primaryModelsSourceRoot: URL {
    projectRoot.appendingPathComponent("AuralisCrypto/Sources/AuralisCrypto/PrimaryModels")
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
