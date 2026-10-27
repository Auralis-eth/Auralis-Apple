import Foundation
import OSLog
import AuralisReceipts

struct AppLaunchConfiguration {
    private static let logger = Logger(subsystem: "Auralis", category: "AppLaunchConfiguration")

    let urlCacheMemoryCapacity: Int
    let urlCacheDiskCapacity: Int
    let urlCacheDirectory: URL?
    /// The CloudKit container backing the external receipt-ledger witness, or `nil`/empty to run
    /// without one. Injected rather than read at the point of use so this is testable and so there is
    /// exactly one place in the app that decides it.
    let receiptWitnessCloudKitContainerIdentifier: String?

    init(
        urlCacheMemoryCapacity: Int = 50 * 1024 * 1024,
        urlCacheDiskCapacity: Int = 500 * 1024 * 1024,
        urlCacheDirectory: URL? = nil,
        receiptWitnessCloudKitContainerIdentifier: String? = Bundle.main.object(
            forInfoDictionaryKey: "AURALIS_RECEIPT_WITNESS_CLOUDKIT_CONTAINER"
        ) as? String
    ) {
        self.urlCacheMemoryCapacity = urlCacheMemoryCapacity
        self.urlCacheDiskCapacity = urlCacheDiskCapacity
        self.urlCacheDirectory = urlCacheDirectory
        self.receiptWitnessCloudKitContainerIdentifier = receiptWitnessCloudKitContainerIdentifier
    }

    /// `@MainActor` because ``ReceiptStores`` is, and the witness identifier has to be set from the
    /// same isolation the store factory reads it on — otherwise the write could not be ordered before
    /// the first store is built, which is the one guarantee this function exists to make.
    /// `AuralisApp.init()` is already main-actor, so this costs the caller nothing.
    @MainActor
    func configure() {
        URLCache.shared = makeURLCache()
        configureReceiptLedgerWitness()
    }

    func makeURLCache() -> URLCache {
        URLCache(
            memoryCapacity: urlCacheMemoryCapacity,
            diskCapacity: urlCacheDiskCapacity,
            directory: urlCacheDirectory
        )
    }

    /// Points the receipt ledger at its external witness, **before anything can build a receipt
    /// store.**
    ///
    /// The ordering requirement is real rather than stylistic: ``ReceiptStores`` memoizes one
    /// persistence store per `ModelContainer` and reads this identifier once, when it builds it — so a
    /// store constructed before this runs keeps an unconfigured witness for the life of the process,
    /// silently, and every ledger in that process is unwitnessed. `AuralisApp.init()` calls
    /// `configure()` as its first statement, ahead of `makePrimaryModelContainer`, which is the
    /// earliest point that ordering can be guaranteed from.
    ///
    /// Deliberately the *only* place the app names the container. Scattering it would mean two call
    /// sites could disagree about whether witnessing is on, and the failure mode of that is a ledger
    /// that reads as witnessed while nothing is publishing for it.
    ///
    /// Empty or absent leaves the witness off, which is the shipping default until the container is
    /// provisioned. That is a safe default rather than a silent one: verification reports the ledger
    /// as unwitnessed, and ``ReceiptLedgerWitnessing`` explains what that costs.
    @MainActor
    private func configureReceiptLedgerWitness() {
        guard let identifier = receiptWitnessCloudKitContainerIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !identifier.isEmpty else {
            Self.logger.info(
                "No receipt-ledger witness container configured; receipt integrity will report ledgers as unwitnessed."
            )
            return
        }
        ReceiptStores.witnessCloudKitContainerIdentifier = identifier
        Self.logger.info(
            "Receipt-ledger witness configured against CloudKit container \(identifier, privacy: .public)."
        )
    }
}
