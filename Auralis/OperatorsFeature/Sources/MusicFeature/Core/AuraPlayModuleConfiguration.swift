import Foundation

/// Snapshot of the app-level bundle contract AuraPlay relies on during the rebuild.
public struct AuraPlayModuleConfiguration: Equatable, Sendable {
    public let backgroundAudioEnabled: Bool
    public let declaredURLSchemes: Set<String>
    public let walletQuerySchemes: Set<String>

    public init(
        backgroundAudioEnabled: Bool,
        declaredURLSchemes: Set<String>,
        walletQuerySchemes: Set<String>
    ) {
        self.backgroundAudioEnabled = backgroundAudioEnabled
        self.declaredURLSchemes = declaredURLSchemes
        self.walletQuerySchemes = walletQuerySchemes
    }

    public var missingRequirements: [String] {
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

    public static func live(infoDictionary: [String: Any]) -> AuraPlayModuleConfiguration {
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
