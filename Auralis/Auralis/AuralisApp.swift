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
            MainView()
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
//NOTES


// MARK: - Helper Functions & Computed Properties
extension String {
    var networkName: String {
        switch self {
            case "0x1":
                return "Ethereum Mainnet"
            case "0x89":
                return "Polygon"
            case "0xaa36a7":
                return "Sepolia Testnet"
            default:
                return "Chain ID: \(self)"
        }
    }

    var formattedChainId: String {
        return "Chain ID: \(self)"
    }
}
