import OSLog
import SwiftData
import SwiftUI

@main
struct AuralisApp: App {
    private let logger = Logger(subsystem: "Auralis", category: "App")

    init() {
        let missingProviders = Secrets.configurationStatuses()
            .filter { !$0.isConfigured }

        if !missingProviders.isEmpty {
            let providerNames = missingProviders.map(\.provider.rawValue).joined(separator: ", ")
            logger.error("Launching with missing provider configuration: \(providerNames, privacy: .public)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainAuraView()
        }
        .modelContainer(for: [EOAccount.self, NFT.self, Tag.self, StoredReceipt.self, Playlist.self, MusicLibraryItem.self, TokenHolding.self, SearchHistoryRecord.self])
    }
}
