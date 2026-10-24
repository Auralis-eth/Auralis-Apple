@testable import Auralis
import AuralisTestSupport
import Foundation
import Testing

@Suite(.tags(.architecture, .slow))
struct AuraPlayBundleContractTests {
    @Test("music bundle contract keeps the required background audio and wallet URL coverage")
    func musicBundleContractKeepsRequiredCapabilities() throws {
        let infoPlist = try loadDictionary(
            atProjectRelativePath: "Auralis/Info.plist"
        )

        let backgroundModes = try #require(infoPlist["UIBackgroundModes"] as? [String])
        #expect(backgroundModes.contains("audio"))
        #expect(backgroundModes.contains("fetch"))

        let backgroundTaskIdentifiers = try #require(infoPlist["BGTaskSchedulerPermittedIdentifiers"] as? [String])
        #expect(backgroundTaskIdentifiers.contains("com.auraplay.nft-sync"))

        let querySchemes = try #require(infoPlist["LSApplicationQueriesSchemes"] as? [String])
        #expect(querySchemes.contains("metamask"))
        #expect(querySchemes.contains("cbwallet"))
        #expect(querySchemes.contains("rainbow"))
        #expect(querySchemes.contains("ledgerlive"))
        #expect(querySchemes.contains("rabby"))
        #expect(querySchemes.contains("phantom"))
        #expect(querySchemes.contains("backpack"))
        #expect(querySchemes.contains("solflare"))

        let walletConnectProjectID = try #require(infoPlist["AURALIS_WALLETCONNECT_PROJECT_ID"] as? String)
        #expect(!walletConnectProjectID.isEmpty)

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

        let configuredCameraUsage = try infoPlistBuildSettingValue(for: "NSCameraUsageDescription")
        let cameraUsage = try #require(
            (infoPlist["NSCameraUsageDescription"] as? String) ?? configuredCameraUsage
        )
        #expect(cameraUsage.localizedCaseInsensitiveContains("camera"))
        #expect(cameraUsage.localizedCaseInsensitiveContains("wallet"))

        let configuredPhotoUsage = try infoPlistBuildSettingValue(for: "NSPhotoLibraryUsageDescription")
        let photoUsage = try #require(
            (infoPlist["NSPhotoLibraryUsageDescription"] as? String) ?? configuredPhotoUsage
        )
        #expect(photoUsage.localizedCaseInsensitiveContains("photo library"))
        #expect(photoUsage.localizedCaseInsensitiveContains("playlist"))

        #expect(infoPlist["NSMotionUsageDescription"] == nil)
    }

    /// Background audio must still need **no** entitlement, and the entitlement file must contain
    /// nothing beyond the three the receipt-ledger witness deliberately introduced.
    ///
    /// This asserted `entitlements.isEmpty`, which expressed the rule only for as long as the file
    /// happened to be empty. The witness work then added an iCloud container, the CloudKit service
    /// and `aps-environment`, and the assertion failed for a change that was intended — while
    /// losing the guarantee it existed for, since "empty" cannot describe a deliberate set.
    ///
    /// Pinning the exact key set keeps the anti-creep property that mattered: a fourth entitlement
    /// cannot appear without someone editing this list and saying why. Each of these is load-bearing
    /// and none is for audio:
    ///
    /// - the two iCloud keys are the external receipt-ledger witness (F-54), and the container
    ///   identifier must stay byte-identical to `AURALIS_RECEIPT_WITNESS_CLOUDKIT_CONTAINER`;
    /// - `aps-environment` is the CloudKit push channel the witness needs to hear about remote
    ///   changes. It is **not yet provisioned** (F-53), which is why no signed build succeeds.
    ///
    /// Adding these had a consequence worth recording here, because this file is where someone will
    /// look: an app-wide iCloud entitlement switches `ModelConfiguration`'s `cloudKitDatabase`
    /// default from a no-op into active SwiftData mirroring, which this schema cannot satisfy. Every
    /// container now opts out explicitly — see `PrimaryStoreSchema.configuration(isStoredInMemoryOnly:)`.
    @Test("app entitlements contain only the deliberate receipt-witness set, and none for audio")
    func musicBundleContractKeepsEntitlementsMinimal() throws {
        let entitlements = try loadDictionary(
            atProjectRelativePath: "Auralis/Auralis.entitlements"
        )

        #expect(
            Set(entitlements.keys) == [
                "aps-environment",
                "com.apple.developer.icloud-container-identifiers",
                "com.apple.developer.icloud-services"
            ],
            "unexpected entitlements: \(entitlements.keys.sorted().joined(separator: ", "))"
        )
        // The witness container, asserted by value: a mismatch with the xcconfig addresses a
        // different container rather than failing, so the ledger would read as witnessed while
        // nothing published for it (F-54).
        #expect(
            entitlements["com.apple.developer.icloud-container-identifiers"] as? [String]
                == ["iCloud.ETH.Auralis.Auralis"]
        )
        #expect(entitlements["com.apple.developer.icloud-services"] as? [String] == ["CloudKit"])
        // The rule this test was originally written for: background audio is declared through
        // `UIBackgroundModes`, not an entitlement.
        #expect(entitlements.keys.contains { $0.localizedCaseInsensitiveContains("audio") } == false)
    }

    @Test("Release builds run provider client key validation")
    func releaseBuildsRunProviderClientKeyValidation() throws {
        let projectRoot = try projectRootURL()
        let projectText = try String(
            contentsOf: projectRoot.appending(path: "Auralis.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        #expect(projectText.contains("Validate Release Secrets"))
        #expect(projectText.contains("Auralis/Scripts/ValidateReleaseSecrets.sh"))
    }

    @Test("Release validation rejects missing and placeholder provider client keys")
    func releaseValidationRejectsMissingAndPlaceholderProviderClientKeys() throws {
        let scriptText = try String(
            contentsOf: try projectRootURL().appending(path: "Auralis/Scripts/ValidateReleaseSecrets.sh"),
            encoding: .utf8
        )

        #expect(scriptText.contains("\"${CONFIGURATION:-}\" != \"Release\""))
        #expect(scriptText.contains("AURALIS_ALCHEMY_API_KEY must be set for Release builds"))
        #expect(scriptText.contains("AURALIS_ALCHEMY_API_KEY contains a placeholder value"))

        for placeholderPattern in [
            "placeholder",
            "changeme",
            "your[-_]?alchemy",
            "^\\$\\(.*\\)$",
            "^api_key$"
        ] {
            #expect(scriptText.contains(placeholderPattern))
        }
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

    /// Xcode may manage usage descriptions as `INFOPLIST_KEY_*` target settings even when the app also
    /// keeps a source Info.plist. Validate the effective declaration instead of requiring one storage form.
    private func infoPlistBuildSettingValue(for key: String) throws -> String? {
        let projectURL = try projectRootURL().appending(path: "Auralis.xcodeproj/project.pbxproj")
        let projectText = try String(contentsOf: projectURL, encoding: .utf8)
        let prefix = "INFOPLIST_KEY_\(key) = \""
        guard let line = projectText.split(separator: "\n").first(where: { $0.contains(prefix) }),
              let valueStart = line.range(of: prefix)?.upperBound,
              let valueEnd = line[valueStart...].firstIndex(of: "\"") else {
            return nil
        }
        return String(line[valueStart..<valueEnd])
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
