//
//  AuralisApp.swift
//  Auralis
//
//  Created by Daniel Bell on 10/20/24.
//

import SwiftData
import SwiftUI

@main
struct AuralisApp: App {
    init() {
        #if !DEBUG
        do {
            try Secrets.validateRequiredProviders([.alchemy])
        } catch {
            preconditionFailure("Release configuration is invalid: \(error.localizedDescription)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainAuraView()
        }
        .modelContainer(for: [EOAccount.self, NFT.self, Tag.self, StoredReceipt.self, Playlist.self, MusicLibraryItem.self, TokenHolding.self, SearchHistoryRecord.self])

#if os(macOS)
        Settings {
            Text("Settings")
        }
        MenuBarExtra {
            Text("Settings")
        }.menuBarExtraStyle(.window)
#endif
    }
}
