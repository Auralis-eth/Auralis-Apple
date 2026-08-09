import Foundation
import WalletConnectorKit

#if os(iOS)
@preconcurrency import ReownAppKit

public struct ReownAppMetadata: Hashable, Sendable {
    public let name: String
    public let description: String
    public let url: String
    public let icons: [String]
    public let redirectNative: String?
    public let redirectUniversal: String?
    public let linkMode: Bool

    public init(
        name: String,
        description: String,
        url: String,
        icons: [String],
        redirectNative: String? = nil,
        redirectUniversal: String? = nil,
        linkMode: Bool = false
    ) {
        self.name = name
        self.description = description
        self.url = url
        self.icons = icons
        self.redirectNative = redirectNative
        self.redirectUniversal = redirectUniversal
        self.linkMode = linkMode
    }

    public static let auraPlayDefault = ReownAppMetadata(
        name: "AuraPlay",
        description: "NFT media player",
        url: "https://auraplay.app",
        icons: ["https://auraplay.app/icon.png"]
    )

    func appMetadata() throws -> AppMetadata {
        try AppMetadata(
            name: name,
            description: description,
            url: url,
            icons: icons,
            redirect: AppMetadata.Redirect(
                native: redirectNative ?? "",
                universal: redirectUniversal,
                linkMode: linkMode
            )
        )
    }
}

@MainActor
public enum ReownAppKitConfiguration {
    private struct ConfigurationKey: Equatable {
        let projectID: String
        let metadata: ReownAppMetadata
    }

    typealias ConfigureDriver = @MainActor (String, AppMetadata, any CryptoProvider, @escaping (Error) -> Void) -> Void

    private static var configuredKey: ConfigurationKey?
    static var configureDriver: ConfigureDriver = defaultConfigureDriver

    public static func configureOnce(
        projectID: String,
        metadata: ReownAppMetadata = .auraPlayDefault,
        crypto: any CryptoProvider,
        onError: @escaping (Error) -> Void = { _ in }
    ) throws {
        let trimmedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectID.isEmpty else {
            throw WalletConnectionError.unavailable("REOWN_PROJECT_ID not set - see README.md")
        }

        let key = ConfigurationKey(projectID: trimmedProjectID, metadata: metadata)
        if let configuredKey {
            guard configuredKey == key else {
                throw WalletConnectionError.unavailable("Reown AppKit is already configured with different metadata or project ID.")
            }
            return
        }

        configureDriver(trimmedProjectID, try metadata.appMetadata(), crypto, onError)
        configuredKey = key
    }

    #if DEBUG
    public static func resetForTesting() {
        configuredKey = nil
        configureDriver = defaultConfigureDriver
    }
    #endif

    private static func defaultConfigureDriver(
        projectID: String,
        metadata: AppMetadata,
        crypto: any CryptoProvider,
        onError: @escaping (Error) -> Void
    ) {
        AppKit.configure(
            projectId: projectID,
            metadata: metadata,
            crypto: crypto,
            authRequestParams: nil,
            onError: onError
        )
    }
}

#endif
