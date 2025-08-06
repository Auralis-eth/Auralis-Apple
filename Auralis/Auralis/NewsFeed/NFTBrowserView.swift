//
//  NFTBrowserView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import SwiftData
import SwiftUI


struct NFTBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var mainAppStore: MainStore
    @Binding var currentAccount: EOAccount?
    @State private var selectedNFT: NFT?
    var nftFetcher = NFTFetcher()

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                if let error = nftFetcher.error as? Moralis.MoralisError {
                    // Error view with updated styling
                    Card3D(cardColor: .error.opacity(0.2)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                SystemImage("exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.error)
                                HeadlineFontText("Error")
                            }

                            switch error {
                                case .invalidData:
                                    SecondaryText("Invalid data returned from server.")
                                case .invalidResponse:
                                    SecondaryText("An unknown error occurred. Please check your connection and try again.")
                            }

                            Button {
                                Task {
                                    await fetchAllNFTs()
                                }
                            } label: {
                                PrimaryText("Try Again")
                                    .fontWeight(.medium)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(Color.secondary)
                                    .cornerRadius(8)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                } else if nftFetcher.loading {
                    // Loading view
                    Card3D(cardColor: .surface) {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                                .progressViewStyle(CircularProgressViewStyle(tint: .secondary))

                            HeadlineFontText("Loading NFTs...")
                                .padding(.top, 16)
                            Card3D(cardColor: .surface) {
                                LoadingProgressView(total: nftFetcher.total, itemsLoaded: nftFetcher.itemsLoaded)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if currentAccount == nil {
                    // Empty wallet view
                    Card3D(cardColor: .surface) {
                        VStack(spacing: 20) {
                            SecondarySystemImage("wallet.pass")
                                .font(.system(size: 60))

                            Title2FontText("Connect Your Wallet")

                            SecondaryText("Please connect your wallet to view your NFTs")
                                .multilineTextAlignment(.center)

                            Button {
                                // Connect wallet action would go here
                            } label: {
                                PrimaryText("Connect Wallet")
                                    .fontWeight(.medium)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                                    .background(Color.secondary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                } else {
                    // NFTs list view
                    NFTListView(mainAppStore: $mainAppStore, currentAccount: $currentAccount, selectedNFT: $selectedNFT)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.background)
        }
        .background(Color.background)
        .refreshable {
            await fetchAllNFTs()
        }
        .onChange(of: currentAccount, initial: false) {
            Task {
                await fetchAllNFTs()
            }
        }
//        .task { @MainActor in
//            await fetchAllNFTs()
//        }
        .sheet(item: $selectedNFT) { nft in
            NFTDetailView(nft: nft)
        }
    }

    func fetchAllNFTs() async {
        guard let accountAddress = currentAccount?.address else {
            return
        }
        do {
            let nfts = try await nftFetcher.fetchAllNFTs(for: accountAddress, chain: mainAppStore.chain)

            guard let nfts else {
                return
            }

            for nft in nfts {
                modelContext.insert(nft)
            }

            do {
                try modelContext.save()
            } catch {
                nftFetcher.error = error
            }

            nfts.forEach { nft in
                let tokenURIs = Set([nft.tokenUri, nft.raw?.tokenUri].compactMap(\.self))
                let siftedTokenURIs = tokenURIs.siftTokenURIs()

                if !siftedTokenURIs.isEmpty, siftedTokenURIs.count > 1 {
                    print("We have elements to parse")
                }


                if !siftedTokenURIs.isEmpty {
                    tokenURIs.forEach { tokenURI in
                        if let decodedTokenURI = tokenURI.base64JSON {
//                            print("Token URI: \(decodedTokenURI)")
                        } else if let url = URL(string: tokenURI) {
                            NFTMetaParser(url: url, tokenURI: tokenURI, nftID: nft.id, modelContext: modelContext)
                                .startParsing()
                        }
                    }
                }
            }

            let nftIDs = nfts.map(\.id)
            let descriptor = FetchDescriptor<NFT>(predicate: #Predicate { !nftIDs.contains($0.id) })
            do {
                try modelContext.enumerate(descriptor) { nft in
                    modelContext.delete(nft)
                }
            } catch {
                print("Failed to retrieve NFTs to SwiftData: \(error)")
                nftFetcher.error = error
            }
        } catch {
            nftFetcher.error = error
        }

        nftFetcher.reset()

    }


}


struct LoadingProgressView: View {
    var total: Int? = nil
    var itemsLoaded: Int? = nil

    private var progressValue: Double {
        guard let total = total, let loaded = itemsLoaded, total > 0 else {
            return 0.0
        }

        if loaded < 0 {
            print("WARNING: itemsLoaded cannot be negative: \(loaded)")
        } else if total < 0 {
            print("WARNING: total cannot be negative: \(total)")
        }

        if loaded > total {
            return 1.0
        } else {
            return Double(loaded) / Double(total)
        }
    }

    private var isIndeterminate: Bool {
        return total != nil && itemsLoaded == nil
    }

    private var isLoading: Bool {
        return total != nil || itemsLoaded != nil
    }

    private var statusText: String {
        if let loaded = itemsLoaded, let total = total {
            if loaded > total {
                return "\(total) loaded"
            } else {
                return "\(loaded) of \(total) loaded"
            }
        } else if total != nil {
            return "Loading..."
        } else {
            return "Waiting to start..."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                if isIndeterminate || progressValue < 0.00 {
                    // Indeterminate progress indicator
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.secondary)
                        .scaleEffect(1.5)
                } else {
                    // Determinate progress bar
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(.secondary)
                        .frame(height: 8)
                        .padding(.horizontal)

                    // Progress percentage
                    HeadlineFontText("\(Int(progressValue * 100))%")
                        .fontWeight(.bold)
                }
            }

            // Status text
            SubheadlineFontText(statusText)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

extension String {
    //// Function to decode a raw token URI string to a dictionary
    var base64JSON: [String: JSONValue]? {
        // Extract the base64 part from the URI
        // Format is: data:application/json;base64,<BASE64_ENCODED_JSON>
        guard let base64StartRange = self.range(of: "base64,") else {
            print("Failed to decode token URI: Missing base64 prefix")
            return nil
        }

        let base64StartIndex = base64StartRange.upperBound
        let base64String = String(self[base64StartIndex...])

        // Decode the base64 string to data
        guard let jsonData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            print("Failed to decode token URI: Invalid base64 encoding")
            return nil
        }

        // Parse the JSON as dictionary
        do {
            guard let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: JSONValue] else {
                print("Failed to decode token URI: JSON could not be converted to dictionary")
                return nil
            }
            return jsonDict
        } catch {
            print("Failed to decode token URI: \(error.localizedDescription)")
            return nil
        }
    }
}

extension Set where Element == String {
    func siftTokenURIs() -> Set<String> {
        // Map canonical resource identifiers to their best URI representation
        var bestURIs: [String: (uri: String, priority: URIFormat)] = [:]
        var otherURIs = Set<String>()

        for uri in self where !uri.isEmpty {

            // Try to find a matching configuration
            var foundMatch = false

            for config in URIConfig.uriConfigurations {
                if uri.hasPrefix(config.prefix) {
                    guard uri.count > config.prefix.count else {
                        otherURIs.insert(uri)
                        continue
                    }

                    let startIndex = uri.index(uri.startIndex, offsetBy: config.prefix.count)
                    let remainder = String(uri[startIndex...])
                    let components = remainder.split(separator: "/", maxSplits: 1)

                    if components.count >= 1, !components[0].isEmpty {
                        let hash = String(components[0])
                        let path = components.count > 1 ? String(components[1]) : ""
                        let resource = NormalizedResource(type: config.type, identifier: hash, path: path)
                        let canonical = resource.canonicalForm

                        if let existing = bestURIs[canonical] {
                            // Keep the higher priority URI format
                            if config.format > existing.priority {
                                bestURIs[canonical] = (uri, config.format)
                            }
                        } else {
                            // First time seeing this resource
                            bestURIs[canonical] = (uri, config.format)
                        }

                        foundMatch = true
                        break
                    }
                }
            }

            if !foundMatch {
                // Not a recognized URI format, keep it as is
                otherURIs.insert(uri)
            }
        }

        // Collect the final results
        var result = Set<String>()

        // Add all the best format URIs
        for (_, uriInfo) in bestURIs {
            result.insert(uriInfo.uri)
        }

        // Add all other URIs
        result.formUnion(otherURIs)

        return result
    }
}

// Define priority for URI formats (higher = better)
enum URIFormat: Int {
    case other = 0
    case content = 1
    case location = 2
    case optimizedLocation = 3

}

extension URIFormat: Comparable {
    static func < (lhs: URIFormat, rhs: URIFormat) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct NormalizedResource {
    enum ResourceType: String {
        case arweave
        case ipfs
        case other
    }

    let type: ResourceType
    let identifier: String
    let path: String

    // Create a canonical representation for deduplication
    var canonicalForm: String {
        "\(type.rawValue):\(identifier):\(path)"
    }
}

struct URIConfig {
    let prefix: String
    let type: NormalizedResource.ResourceType
    let format: URIFormat
    // Define all URI configurations
    static let uriConfigurations: [URIConfig] = [
        URIConfig(prefix: "ar://", type: .arweave, format: .content),
        URIConfig(prefix: "https://arweave.net/", type: .arweave, format: .location),
        URIConfig(prefix: "ipfs://", type: .ipfs, format: .content),
        URIConfig(prefix: "https://ipfs.io/ipfs/", type: .ipfs, format: .location),
        URIConfig(prefix: "https://alchemy.mypinata.cloud/ipfs/", type: .ipfs, format: .optimizedLocation)
    ]

}

enum ArweaveURLConversionError: Error {
    case unsupportedFormat
    case invalidTransactionID

    var description: String {
        switch self {
        case .unsupportedFormat:
            return "Unsupported URL format. URL must start with 'ar://' or 'https://arweave.net/'"
        case .invalidTransactionID:
            return "Invalid transaction ID. Transaction ID must be 43 characters and base64url-encoded"
        }
    }
}

struct ArweaveURLConverter {
    // Base gateway URL
    private static let gatewayBaseURL = "https://arweave.net/"
    private static let nativePrefix = "ar://"

    // Regular expression to validate transaction ID (43 characters base64url-encoded)
    private static let transactionIDRegex = "^[a-zA-Z0-9_-]{43}$"

    /// Converts between Arweave native URI and Arweave gateway URL
    /// - Parameter urlString: The URL string to convert (ar:// URI or https://arweave.net/ URL)
    /// - Returns: The converted URL string
    /// - Throws: ArweaveURLConversionError if the input is invalid
    static func convertURL(_ urlString: String) throws -> String {
        if urlString.starts(with: nativePrefix) {
            return try convertNativeToGateway(urlString)
        } else if urlString.starts(with: gatewayBaseURL) {
            return try convertGatewayToNative(urlString)
        } else {
            throw ArweaveURLConversionError.unsupportedFormat
        }
    }

    /// Converts Arweave native URI to gateway URL
    /// - Parameter nativeURI: The ar:// URI to convert
    /// - Returns: The gateway URL
    /// - Throws: ArweaveURLConversionError if the input is invalid
    static func convertNativeToGateway(_ nativeURI: String) throws -> String {
        let afterPrefix = nativeURI.dropFirst(nativePrefix.count)

        // Extract the transaction ID (which is either everything if there's no path,
        // or everything up to the first '/')
        let components = String(afterPrefix).components(separatedBy: "/")
        let transactionID = components[0]

        // Validate transaction ID
        if !isValidTransactionID(transactionID) {
            throw ArweaveURLConversionError.invalidTransactionID
        }

        // Reconstruct URL with the gateway base
        if components.count > 1 {
            // Join the path components back together
            let path = components.dropFirst().joined(separator: "/")
            return "\(gatewayBaseURL)\(transactionID)/\(path)"
        } else {
            return "\(gatewayBaseURL)\(transactionID)"
        }
    }

    /// Converts gateway URL to Arweave native URI
    /// - Parameter gatewayURL: The gateway URL to convert
    /// - Returns: The ar:// URI
    /// - Throws: ArweaveURLConversionError if the input is invalid
    static func convertGatewayToNative(_ gatewayURL: String) throws -> String {
        let afterPrefix = gatewayURL.dropFirst(gatewayBaseURL.count)

        // Extract the transaction ID (which is either everything if there's no path,
        // or everything up to the first '/')
        let components = String(afterPrefix).components(separatedBy: "/")
        let transactionID = components[0]

        // Validate transaction ID
        if !isValidTransactionID(transactionID) {
            throw ArweaveURLConversionError.invalidTransactionID
        }

        // Reconstruct URL with the native prefix
        if components.count > 1 {
            // Join the path components back together
            let path = components.dropFirst().joined(separator: "/")
            return "\(nativePrefix)\(transactionID)/\(path)"
        } else {
            return "\(nativePrefix)\(transactionID)"
        }
    }

    /// Validates if a transaction ID has the correct format
    /// - Parameter transactionID: The transaction ID to validate
    /// - Returns: True if valid, false otherwise
    private static func isValidTransactionID(_ transactionID: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: transactionIDRegex) else {
            return false
        }

        let range = NSRange(location: 0, length: transactionID.utf16.count)
        return regex.firstMatch(in: transactionID, options: [], range: range) != nil
    }
}

class NFTMetaParser {
    let url: URL
    let tokenURI: String
    let nftID: String
    var task: Task<Void, Never>?
    private let modelContext: ModelContext

    init(url: URL, tokenURI: String, nftID: String, modelContext: ModelContext) {
        self.url = url
        self.tokenURI = tokenURI
        self.nftID = nftID
        self.modelContext = modelContext
    }

    public func startParsing() {
        task = Task {
            // 1. Normalize URL first
            let normalizedURL = await normalizeURL(from: url, originalTokenURI: tokenURI)

            // 2. Ensure we have a secure URL
            guard let secureURL = normalizedURL, secureURL.scheme == "https" else {
                return
            }

            // 3. Fetch and process data
            await fetchAndProcessData(from: secureURL)
        }
    }

    // Helper function to normalize URLs based on their type
    private func normalizeURL(from url: URL, originalTokenURI: String) async -> URL? {
        if url.isIPFS, let ipfsHTML = url.ipfsHTML {
            return ipfsHTML
        } else if url.scheme == "ar",
                  let arWeaveURLString = try? ArweaveURLConverter.convertURL(originalTokenURI),
                  let arWeaveURL = URL(string: arWeaveURLString) {
            return arWeaveURL
        } else if url.scheme?.lowercased() == "http",
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if components.scheme?.lowercased() == "http" {
                components.scheme = "https"
            }
            return components.url ?? url
        } else if url.scheme != "https" {
            print("Token URI: \(url.absoluteString)")
            return nil
        }

        return url
    }

    // Helper function to fetch and process data from a URL
    private func fetchAndProcessData(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await processResponseData(data, from: url)
        } catch {
            await handleNetworkError(error as NSError)
        }
    }

    // Process the response data
    private func processResponseData(_ data: Data, from url: URL) async {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: JSONValue] else {
                print(String(data: data, encoding: .utf8) ?? "Invalid Dictionary data")
                return
            }

            // Retrieve and update NFT in SwiftData
            await MainActor.run {
                do {
                    let descriptor = FetchDescriptor<NFT>(predicate: #Predicate { return $0.id == nftID })
                    // Fetch the NFT from SwiftData
                    guard let fetchedNFTs = try? modelContext.fetch(descriptor), let nft = fetchedNFTs.first else {
                        print("NFT with ID \(nftID) not found in database")
                        return
                    }

                    // Use the shared utility function to update NFT properties
                    NFTMetadataUpdater.updateNFTFromMetadata(nft: nft, metadata: json)

                    // Save the changes
                    try self.modelContext.save()
                } catch {
                    print("Error updating NFT in SwiftData: \(error)")
                }
            }
        } catch {
            // The URL was not a JSON endpoint, handle other content types
            print("Error parsing JSON: \(error)")
            guard let content = String(data: data, encoding: .utf8) else { return }

            if content.contains("<html>") {
                await MainActor.run {
                    do {
                        let descriptor = FetchDescriptor<NFT>(predicate: #Predicate { return $0.id == nftID })
                        guard let fetchedNFTs = try? modelContext.fetch(descriptor), let nft = fetchedNFTs.first else {
                            return
                        }

                        nft.contentType = "website"
                        nft.website = url.absoluteString // Store the website URL

                        try self.modelContext.save()
                    } catch {
                        print("Error updating NFT content type to website: \(error)")
                    }
                }
            } else {
                print(String(data: data, encoding: .utf8) ?? "Invalid UTF-8 data")
            }
        }
    }

    // Handle network errors with comprehensive error handling
    private func handleNetworkError(_ nsError: NSError) async {
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            print("Network connection error for URL \(url.absoluteString): \(nsError.localizedDescription)")
        case NSURLErrorTimedOut:
            print("Connection timed out for URL: \(url.absoluteString)")
        case NSURLErrorCannotFindHost:
            print("Cannot find host for URL: \(url.absoluteString)")
        case NSURLErrorServerCertificateUntrusted:
            print("Server certificate untrusted for URL: \(url.absoluteString)")
        default:
            print("Network error for URL \(url.absoluteString): \(nsError)")
        }
    }
}

// MARK: - NFTMetadataUpdater Utility Class
class NFTMetadataUpdater {
    static func updateNFTFromMetadata(nft: NFT, metadata: [String : JSONValue]?) {
        guard let metadata else {
            return
        }
        // Basic Information
        if let name = metadata["name"] {
            nft.name = name.stringValue
        } else if let artworkName = metadata["artworkName"] {
            nft.name = artworkName.stringValue
        }

        if let description = metadata["description"] {
            nft.nftDescription = description.stringValue
        }

        // Collection Information
        if let collection = metadata["collection"], let collectionName = collection.objectValue?["name"] {
            nft.collectionName = collectionName.stringValue
        } else if let collectionName = metadata["collectionName"] {
            nft.collectionName = collectionName.stringValue
        }

        // Additional Collection Information
        if let collectionID = metadata["collectionID"] {
            nft.collectionID = collectionID.stringValue
        }
        if let projectID = metadata["projectID"] {
            nft.projectID = projectID.stringValue
        }
        if let series = metadata["series"] {
            nft.series = series.stringValue
        }
        if let seriesID = metadata["seriesID"] {
            nft.seriesID = seriesID.stringValue
        }

        // Artist/Creator Information
        if let artistName = metadata["artist_name"] {
            nft.artistName = artistName.stringValue
        } else if let artist = metadata["artist"] {
            nft.artistName = artist.stringValue
        } else if let creator = metadata["creator"] {
            nft.artistName = creator.stringValue
        } else if let createdBy = metadata["createdBy"] {
            nft.artistName = createdBy.stringValue
        }

        // Additional Artist Information
        if let artistWebsite = metadata["artistWebsite"] {
            nft.artistWebsite = artistWebsite.stringValue
        }

        // Media URLs - Optimized with helper function
        updateImageURLs(nft: nft, metadata: metadata)
        updateAnimationURLs(nft: nft, metadata: metadata)
        updateAudioURLs(nft: nft, metadata: metadata)
        updateExternalURLs(nft: nft, metadata: metadata)
        updateModelURLs(nft: nft, metadata: metadata)

        // Handle token IDs
        if let tokenID = metadata["tokenID"]?.intValue {
            nft.tokenId = String(tokenID)
        } else if let tokenID = metadata["tokenId"]?.intValue {
            nft.tokenId = String(tokenID)
        } else if let tokenIDString = metadata["tokenID"]?.stringValue ?? metadata["tokenId"]?.stringValue {
            nft.tokenId = tokenIDString
        }

        // Handle unique ID
        if let uniqueID = metadata["id"]?.stringValue {
            nft.uniqueID = uniqueID
        }

        // Handle timestamp and token hash
        if let timestamp = metadata["timestamp"]?.stringValue {
            nft.timestamp = timestamp
        }
        if let tokenHash = metadata["tokenHash"]?.stringValue {
            nft.tokenHash = tokenHash
        }

        // Handle metadata properties
        updateMetadataProperties(nft: nft, metadata: metadata)

        // Handle numeric properties
        updateNumericProperties(nft: nft, metadata: metadata)

        // Handle traits/attributes
        updateTraitsAndAttributes(nft: nft, metadata: metadata)
    }

    // MARK: - Helper Methods for URL Updates
    private static func updateImageURLs(nft: NFT, metadata: [String: JSONValue]) {
        // Handle main image URLs
        if let imageURLString = metadata["image"]?.stringValue ?? metadata["imageUrl"]?.stringValue {
            nft.image?.originalUrl = imageURLString
            if let imageURL = URL(string: imageURLString) {
                nft.image?.secureUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle specialized image URLs
        if let primaryAssetUrl = metadata["primaryAssetUrl"]?.stringValue {
            nft.primaryAssetUrl = primaryAssetUrl
            if let assetURL = URL(string: primaryAssetUrl) {
                nft.securePrimaryAssetUrl = ensureSecureURL(assetURL)?.absoluteString
            }
        }

        if let previewAssetUrl = metadata["previewAssetUrl"]?.stringValue {
            nft.previewAssetUrl = previewAssetUrl
            if let assetURL = URL(string: previewAssetUrl) {
                nft.securePreviewAssetUrl = ensureSecureURL(assetURL)?.absoluteString
            }
        }

        if let imageDataUrl = metadata["imageData"]?.stringValue {
            nft.imageDataUrl = imageDataUrl
            if let imageURL = URL(string: imageDataUrl) {
                nft.secureImageDataUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        if let imageHrUrl = metadata["imageHrUrl"]?.stringValue {
            nft.imageHrUrl = imageHrUrl
            if let imageURL = URL(string: imageHrUrl) {
                nft.secureImageHrUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        if let imageHash = metadata["imageHash"]?.stringValue {
            nft.imageHash = imageHash
        }
    }

    private static func updateAnimationURLs(nft: NFT, metadata: [String: JSONValue]) {
        if let animationURLString = metadata["animation_url"]?.stringValue ?? metadata["animationUrl"]?.stringValue ?? metadata["animation"]?.stringValue {
            nft.animationUrl = animationURLString
            if let animationURL = URL(string: animationURLString) {
                nft.secureAnimationUrl = ensureSecureURL(animationURL)?.absoluteString
            }
        }
    }

    private static func updateAudioURLs(nft: NFT, metadata: [String: JSONValue]) {
        let audioURLString = metadata["audioUrl"]?.stringValue ??
                           metadata["audioURI"]?.stringValue ??
                           metadata["audio"]?.stringValue ??
                           metadata["losslessAudio"]?.stringValue
        if let audioURLString = audioURLString {
            nft.audioUrl = audioURLString
        }
    }

    private static func updateExternalURLs(nft: NFT, metadata: [String: JSONValue]) {
        if let externalURLString = metadata["external_url"]?.stringValue ?? metadata["externalUrl"]?.stringValue ?? metadata["external_link"]?.stringValue {
            nft.externalUrl = externalURLString
        } else if let externals = metadata["external_url"]?.objectValue ?? metadata["externalUrl"]?.objectValue,
                  let externalURLString = externals["url"]?.stringValue {
            nft.externalUrl = externalURLString
        }
    }

    private static func updateModelURLs(nft: NFT, metadata: [String: JSONValue]) {
        let modelURLString = metadata["modelGlb"]?.stringValue ??
                           metadata["vrmUrl"]?.stringValue ??
                           metadata["usdzUrl"]?.stringValue ??
                           metadata["print3DSTL"]?.stringValue
        if let modelURLString = modelURLString {
            nft.modelUrl = modelURLString
        }
    }

    private static func updateMetadataProperties(nft: NFT, metadata: [String: JSONValue]) {
        if let backgroundColor = metadata["background_color"]?.stringValue ?? metadata["backgroundColor"]?.stringValue {
            nft.backgroundColor = backgroundColor
        }
        if let medium = metadata["medium"]?.stringValue {
            nft.medium = medium
        }
        if let metadataVersion = metadata["metadataVersion"]?.stringValue {
            nft.metadataVersion = metadataVersion
        }
        if let symbols = metadata["symbols"]?.stringValue {
            nft.symbols = symbols
        }
        if let seed = metadata["seed"]?.stringValue {
            nft.seed = seed
        }
        if let original = metadata["original"]?.stringValue {
            nft.original = original
        }
        if let agreement = metadata["agreement"]?.stringValue {
            nft.agreement = agreement
        }
        if let website = metadata["website"]?.stringValue {
            nft.website = website
        }
        if let payoutAddress = metadata["payoutAddress"]?.stringValue {
            nft.payoutAddress = payoutAddress
        }
        if let scriptType = metadata["scriptType"]?.stringValue {
            nft.scriptType = scriptType
        }
        if let engineType = metadata["engineType"]?.stringValue {
            nft.engineType = engineType
        }
        if let accessArtworkFiles = metadata["accessArtworkFiles"]?.stringValue {
            nft.accessArtworkFiles = accessArtworkFiles
        }
    }

    private static func updateNumericProperties(nft: NFT, metadata: [String: JSONValue]) {
        if let sellerFeeBasisPoints = metadata["sellerFeeBasisPoints"]?.intValue {
            nft.sellerFeeBasisPoints = sellerFeeBasisPoints
        }
        if let minted = metadata["minted"]?.intValue {
            nft.minted = minted
        }
        if let isStatic = metadata["isStatic"]?.intValue {
            nft.isStatic = isStatic
        }
        if let aspectRatio = metadata["aspectRatio"]?.doubleValue {
            nft.aspectRatio = aspectRatio
        }
    }

    private static func updateTraitsAndAttributes(nft: NFT, metadata: [String: JSONValue]) {
        if let attributesArray = metadata["attributes"]?.arrayValue  {//as? [[String: Any]]
            nft.attributes = attributesArray.compactMap {
                guard let attribute = $0.objectValue else {
                    return nil
                }

                guard let value = attribute["value"]?.stringValue else {
                    return nil
                }

                return NFT.Attribute(
                    value: value,
                    traitType: attribute["type"]?.stringValue ?? attribute["trait_type"]?.stringValue
                )
            }
        } else if let traitsArray = metadata["traits"]?.arrayValue {
            nft.attributes = traitsArray.compactMap {
                guard let traitDict = $0.objectValue else {
                    return nil
                }

                guard let value = traitDict["value"]?.stringValue else {
                    return nil
                }
                return NFT.Attribute(
                    value: value,
                    traitType: traitDict["type"]?.stringValue ?? traitDict["trait_type"]?.stringValue
                )
            }
        }
    }

    // Helper function to ensure URLs are secure (HTTPS) or point to a gateway
    private static func ensureSecureURL(_ url: URL) -> URL? {
        if url.isIPFS, let ipfsGatewayURL = url.ipfsHTML {
            return ipfsGatewayURL
        } else if url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            return components.url
        }
        return url
    }
}
