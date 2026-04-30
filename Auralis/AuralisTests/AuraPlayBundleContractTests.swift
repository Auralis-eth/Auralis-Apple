@testable import Auralis
import Foundation
import Testing

@Suite
struct AuraPlayBundleContractTests {
    @Test("music bundle contract keeps the required background audio and wallet URL coverage")
    func musicBundleContractKeepsRequiredCapabilities() throws {
        let infoPlist = try loadDictionary(
            atProjectRelativePath: "Auralis/Info.plist"
        )

        let backgroundModes = try #require(infoPlist["UIBackgroundModes"] as? [String])
        #expect(backgroundModes.contains("audio"))

        let querySchemes = try #require(infoPlist["LSApplicationQueriesSchemes"] as? [String])
        #expect(querySchemes.contains("metamask"))
        #expect(querySchemes.contains("cbwallet"))
        #expect(querySchemes.contains("rainbow"))
        #expect(querySchemes.contains("ledgerlive"))

        let urlTypes = try #require(infoPlist["CFBundleURLTypes"] as? [[String: Any]])
        let declaredSchemes = urlTypes
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(declaredSchemes.contains("auralis"))
        #expect(declaredSchemes.contains("auraplay"))
    }

    @Test("music privacy strings stay aligned with implemented camera and photo flows")
    func musicPrivacyStringsStayHonest() throws {
        let infoPlist = try loadDictionary(
            atProjectRelativePath: "Auralis/Info.plist"
        )

        let cameraUsage = try #require(infoPlist["NSCameraUsageDescription"] as? String)
        #expect(cameraUsage.localizedCaseInsensitiveContains("camera"))
        #expect(cameraUsage.localizedCaseInsensitiveContains("wallet"))

        let photoUsage = try #require(infoPlist["NSPhotoLibraryUsageDescription"] as? String)
        #expect(photoUsage.localizedCaseInsensitiveContains("photo library"))
        #expect(photoUsage.localizedCaseInsensitiveContains("playlist"))

        #expect(infoPlist["NSMotionUsageDescription"] == nil)
    }

    @Test("music bundle contract does not rely on extra entitlements for background audio")
    func musicBundleContractKeepsEntitlementsMinimal() throws {
        let entitlements = try loadDictionary(
            atProjectRelativePath: "Auralis/Auralis.entitlements"
        )

        #expect(entitlements.isEmpty)
    }

    private func loadDictionary(
        atProjectRelativePath relativePath: String
    ) throws -> [String: Any] {
        let fileURL = try projectRootURL().appending(path: relativePath)
        guard
            let dictionary = NSDictionary(contentsOf: fileURL) as? [String: Any]
        else {
            Issue.record("Unable to load plist at \(fileURL.path())")
            throw BundleFixtureError()
        }
        return dictionary
    }

    private func projectRootURL(filePath: String = #filePath) throws -> URL {
        var candidate = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()

        while candidate.path != "/" {
            let projectPath = candidate.appending(path: "Auralis.xcodeproj").path()
            if FileManager.default.fileExists(atPath: projectPath) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        Issue.record("Unable to locate project root from \(filePath)")
        throw BundleFixtureError()
    }
}

private struct BundleFixtureError: Error {}
