import Foundation
import Testing

@Suite
struct AuraPlayPrivacyManifestTests {
    @Test("privacy manifest covers the current AuraPlay rebuild contract without extra required-reason APIs")
    func privacyManifestMatchesCurrentAuraPlayContract() throws {
        let manifest = try loadDictionary(
            atProjectRelativePath: "Auralis/PrivacyInfo.xcprivacy"
        )

        let accessedAPIs = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let fileTimestampEntry = try #require(
            accessedAPIs.first {
                ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryFileTimestamp"
            }
        )
        let fileTimestampReasons = try #require(
            fileTimestampEntry["NSPrivacyAccessedAPITypeReasons"] as? [String]
        )
        let userDefaultsEntry = try #require(
            accessedAPIs.first {
                ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults"
            }
        )
        let reasons = try #require(userDefaultsEntry["NSPrivacyAccessedAPITypeReasons"] as? [String])

        #expect(fileTimestampReasons == ["C617.1"])
        #expect(reasons == ["CA92.1"])
        #expect(accessedAPIs.count == 2)
    }

    private func loadDictionary(
        atProjectRelativePath relativePath: String
    ) throws -> [String: Any] {
        let fileURL = try projectRootURL().appending(path: relativePath)
        guard
            let dictionary = NSDictionary(contentsOf: fileURL) as? [String: Any]
        else {
            Issue.record("Unable to load plist at \(fileURL.path())")
            throw PrivacyManifestFixtureError()
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
        throw PrivacyManifestFixtureError()
    }
}

private struct PrivacyManifestFixtureError: Error {}
