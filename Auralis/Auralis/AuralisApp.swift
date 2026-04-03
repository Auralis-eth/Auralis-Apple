//
//  AuralisApp.swift
//  Auralis
//
//  Created by Daniel Bell on 10/20/24.
//

import SwiftUI
import SwiftData

@main
struct AuralisApp: App {
    var body: some Scene {
        WindowGroup {
            MainAuraView()
//                .task {
//                    await runMetadataAnalysis()
//                }
        }
        .modelContainer(for: [EOAccount.self, NFT.self, Tag.self, StoredReceipt.self, Playlist.self, MusicLibraryItem.self, TokenHolding.self])

#if os(macOS)
        Settings {
            Text("Settings")
        }
        //MenuBarExtra(content: <#T##() -> _#>, label: <#T##() -> _#>)
        MenuBarExtra {
            Text("Settings")
        }.menuBarExtraStyle(.window)
#endif
    }
}
