import Foundation

/// Snapshot of the app-level bundle contract AuraPlay relies on during the rebuild.
struct AuraPlayModuleConfiguration: Equatable, Sendable {
    let backgroundAudioEnabled: Bool
    let declaredURLSchemes: Set<String>
    let walletQuerySchemes: Set<String>

    var missingRequirements: [String] {
        var requirements: [String] = []

        if !backgroundAudioEnabled {
            requirements.append("Background audio mode is missing.")
        }
        if !declaredURLSchemes.contains("auraplay") {
            requirements.append("The auraplay URL scheme is missing.")
        }
        if !declaredURLSchemes.contains("auralis") {
            requirements.append("The auralis URL scheme is missing.")
        }

        let requiredWalletSchemes: Set<String> = ["metamask", "cbwallet", "rainbow", "ledgerlive"]
        let missingWalletSchemes = requiredWalletSchemes.subtracting(walletQuerySchemes)
        if !missingWalletSchemes.isEmpty {
            let joinedSchemes = missingWalletSchemes.sorted().joined(separator: ", ")
            requirements.append("Wallet query schemes missing: \(joinedSchemes).")
        }

        return requirements
    }

    static func live(infoDictionary: [String: Any]) -> AuraPlayModuleConfiguration {
        let backgroundModes = Set(infoDictionary["UIBackgroundModes"] as? [String] ?? [])
        let declaredURLSchemes = Set(
            (infoDictionary["CFBundleURLTypes"] as? [[String: Any]] ?? [])
                .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )
        let walletQuerySchemes = Set(infoDictionary["LSApplicationQueriesSchemes"] as? [String] ?? [])

        return AuraPlayModuleConfiguration(
            backgroundAudioEnabled: backgroundModes.contains("audio"),
            declaredURLSchemes: declaredURLSchemes,
            walletQuerySchemes: walletQuerySchemes
        )
    }
}
