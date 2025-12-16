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
                .modelContainer(for: [NFT.self, EOAccount.self, Tag.self])
//                .task {
//                    await runMetadataAnalysis()
//                }
        }

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
