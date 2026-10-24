@testable import Auralis
import Foundation
import ReceiptStorage
import Testing

struct AuraPlayCacheLaunchConfigurationTests {
    @Test("app launch configuration uses the Phase 5 artwork URLCache capacities")
    func urlCacheCapacityContract() {
        let cache = AppLaunchConfiguration().makeURLCache()

        #expect(cache.memoryCapacity == 50 * 1024 * 1024)
        #expect(cache.diskCapacity == 500 * 1024 * 1024)
    }

    /// `@MainActor` because `configure()` now also points the receipt ledger at its external witness,
    /// and that has to happen on the same isolation `ReceiptStores` reads it from — see
    /// `AppLaunchConfiguration.configureReceiptLedgerWitness()`.
    @MainActor
    @Test("app launch configuration installs the configured shared URLCache")
    func configureInstallsSharedURLCache() {
        let previousCache = URLCache.shared
        defer { URLCache.shared = previousCache }

        let configuration = AppLaunchConfiguration(
            urlCacheMemoryCapacity: 8 * 1024 * 1024,
            urlCacheDiskCapacity: 64 * 1024 * 1024,
            urlCacheDirectory: nil,
            // Explicitly none, so this test cannot depend on the build's witness configuration and
            // cannot leave a container identifier set for whatever runs after it.
            receiptWitnessCloudKitContainerIdentifier: nil
        )

        configuration.configure()

        #expect(URLCache.shared.memoryCapacity == 8 * 1024 * 1024)
        #expect(URLCache.shared.diskCapacity == 64 * 1024 * 1024)
    }

    /// The bootstrap contract that matters for integrity: an empty or whitespace-only identifier must
    /// leave the witness off rather than handing CloudKit a container name it cannot use.
    ///
    /// The config key ships empty until the container is provisioned, and an xcconfig substitution
    /// that resolves to nothing arrives here as `""` rather than as absent — so the empty case is the
    /// shipping path, not an edge case.
    @MainActor
    @Test("a blank witness container identifier leaves the witness unconfigured")
    func blankWitnessIdentifierLeavesWitnessOff() {
        let previous = ReceiptStores.witnessCloudKitContainerIdentifier
        defer { ReceiptStores.witnessCloudKitContainerIdentifier = previous }

        for blank in ["", "   ", "\n"] {
            ReceiptStores.witnessCloudKitContainerIdentifier = nil
            AppLaunchConfiguration(receiptWitnessCloudKitContainerIdentifier: blank).configure()
            #expect(
                ReceiptStores.witnessCloudKitContainerIdentifier == nil,
                "a blank identifier (\(blank.debugDescription)) configured a witness"
            )
        }
    }

    @MainActor
    @Test("a configured witness container identifier reaches the receipt store factory")
    func configuredWitnessIdentifierIsInstalled() {
        let previous = ReceiptStores.witnessCloudKitContainerIdentifier
        defer { ReceiptStores.witnessCloudKitContainerIdentifier = previous }

        ReceiptStores.witnessCloudKitContainerIdentifier = nil
        AppLaunchConfiguration(
            // Trailing whitespace on purpose: xcconfig values pick it up easily and CloudKit would
            // take the padded string as a different container.
            receiptWitnessCloudKitContainerIdentifier: " iCloud.ETH.Auralis.Auralis "
        ).configure()

        #expect(ReceiptStores.witnessCloudKitContainerIdentifier == "iCloud.ETH.Auralis.Auralis")
    }
}
