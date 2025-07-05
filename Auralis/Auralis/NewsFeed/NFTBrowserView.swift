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
    var base64JSON: [String: Any]? {
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
            guard let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
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
            await processResponseData(data)
        } catch {
            await handleNetworkError(error as NSError)
        }
    }

    // Process the response data
    private func processResponseData(_ data: Data) async {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
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

                    // Basic Information
                    if let name = json[.name] as? String {
                        nft.name = name
                    } else if let artworkName = json[.artworkName] as? String {
                        nft.name = artworkName
                    }

                    if let description = json[.description] as? String {
                        nft.nftDescription = description
                    }

                    // Collection Information
                    if let collection = json["collection"] as? [String: Any], let collectionName = collection[.name] as? String {
                        nft.collectionName = collectionName
                    } else if let collectionName = json[.collectionName] as? String {
                        nft.collectionName = collectionName
                    }

                    // Additional Collection Information
                    if let collectionID = json[.collectionID] as? String {
                        nft.collectionID = collectionID
                    }

                    if let projectID = json[.projectID] as? String {
                        nft.projectID = projectID
                    }

                    if let series = json[.series] as? String {
                        nft.series = series
                    }

                    if let seriesID = json[.seriesID] as? String {
                        nft.seriesID = seriesID
                    }

                    // Artist/Creator Information
                    if let artistName = json["artist_name"] as? String {
                        nft.artistName = artistName
                    } else if let artist = json[.artist] as? String {
                        nft.artistName = artist
                    } else if let creator = json[.creator] as? String {
                        nft.artistName = creator
                    } else if let createdBy = json[.createdBy] as? String {
                        nft.artistName = createdBy
                    }

                    // Additional Artist Information
                    if let artistWebsite = json[.artistWebsite] as? String {
                        nft.artistWebsite = artistWebsite
                    }

//                    if let artistRoyalty = json[.artistRoyalty] as? [String: Any] {
//                        nft.artistRoyalty = artistRoyalty
//                    }

                    // Media URLs
                    // First handle image URLs
                    if let imageURLString = json[.image] as? String {
                        nft.image?.originalUrl = imageURLString
                        if let imageURL = URL(string: imageURLString) {
                            nft.image?.secureUrl = ensureSecureURL(imageURL)?.absoluteString
                        }
                    }

                    if let imageURLString = json[.imageUrl] as? String {
                        nft.image?.originalUrl = imageURLString
                        if let imageURL = URL(string: imageURLString) {
                            nft.image?.secureUrl = ensureSecureURL(imageURL)?.absoluteString
                        }
                    }

                    // Handle primary asset URLs
                    if let primaryAssetUrl = json[.primaryAssetUrl] as? String {
                        nft.primaryAssetUrl = primaryAssetUrl
                        if let imageURL = URL(string: primaryAssetUrl) {
                            nft.securePrimaryAssetUrl = ensureSecureURL(imageURL)?.absoluteString
                        }
                    }

                    // Handle preview asset URLs
                    if let previewAssetUrl = json[.previewAssetUrl] as? String {
                        nft.previewAssetUrl = previewAssetUrl
                        if let imageURL = URL(string: previewAssetUrl) {
                            nft.securePreviewAssetUrl = ensureSecureURL(imageURL)?.absoluteString
                        }
                    }

                    // Handle image data
                    if let imageDataUrl = json[.imageData] as? String {
                        nft.imageDataUrl = imageDataUrl
                        if let imageURL = URL(string: imageDataUrl) {
                            nft.secureImageDataUrl = ensureSecureURL(imageURL)?.absoluteString
                        }
                    }

                    // Handle high-resolution image
                    if let imageHrUrl = json[.imageHrUrl] as? String {
                        nft.imageHrUrl = imageHrUrl
                        if let imageURL = URL(string: imageHrUrl) {
                            nft.secureImageHrUrl = ensureSecureURL(imageURL)?.absoluteString
                        }
                    }

                    // Handle image hash and details
                    if let imageHash = json[.imageHash] as? String {
                        nft.imageHash = imageHash
                    }

//                    if let imageDetails = json[.imageDetails] as? [String: Any] {
//                        nft.imageDetails = imageDetails
//                    }

                    // Then handle animation URLs
                    if let animationURLString = json[.animationUrl] as? String, let animationURL = URL(string: animationURLString) {
                        nft.animationUrl = animationURLString
                        nft.secureAnimationUrl = ensureSecureURL(animationURL)?.absoluteString
                    } else if let animationURLString = json[.animation] as? String, let animationURL = URL(string: animationURLString) {
                        nft.animationUrl = animationURLString
                        nft.secureAnimationUrl = ensureSecureURL(animationURL)?.absoluteString
                    }

                    // Handle animation details
//                    if let animationDetails = json[.animationDetails] as? [String: Any] {
//                        nft.animationDetails = animationDetails
//                    }

                    // Handle audio URLs
                    if let audioURLString = json[.audioUrl] as? String {
                        nft.audioUrl = audioURLString
                    } else if let audioURLString = json[.audioURI] as? String {
                        nft.audioUrl = audioURLString
                    } else if let audioURLString = json[.audio] as? String {
                        nft.audioUrl = audioURLString
                    } else if let audioURLString = json[.losslessAudio] as? String {
                        nft.audioUrl = audioURLString
                    }

                    // Handle external URLs/links
                    if let externalURLString = json[.externalUrl] as? String {
                        nft.externalUrl = externalURLString
                    } else if let externalURLString = json["external_link"] as? String {
                        nft.externalUrl = externalURLString
                    } else if let externals = json[.externalUrl] as? [String: Any],
                              let externalURLString = externals["url"] as? String {
                        nft.externalUrl = externalURLString
                    }

                    // Handle 3D model URLs
                    if let modelURLString = json[.modelGlb] as? String {
                        nft.modelUrl = modelURLString
                    } else if let modelURLString = json[.vrmUrl] as? String {
                        nft.modelUrl = modelURLString
                    } else if let modelURLString = json[.usdzUrl] as? String {
                        nft.modelUrl = modelURLString
                    } else if let modelURLString = json[.print3DSTL] as? String {
                        nft.modelUrl = modelURLString
                    }

                    // Handle token IDs
                    if let tokenID = json[.tokenID] as? Int {
                        nft.tokenId = String(tokenID)
                    } else if let tokenID = json[.tokenId] as? Int {
                        nft.tokenId = String(tokenID)
                    } else if let tokenIDString = json[.tokenID] as? String {
                        nft.tokenId = tokenIDString
                    } else if let tokenIDString = json[.tokenId] as? String {
                        nft.tokenId = tokenIDString
                    }

                    // Handle unique ID
                    if let uniqueID = json[.id] as? String {
                        nft.uniqueID = uniqueID
                    }

                    // Handle timestamp and token hash
                    if let timestamp = json[.timestamp] as? String {
                        nft.timestamp = timestamp
                    }

                    if let tokenHash = json[.tokenHash] as? String {
                        nft.tokenHash = tokenHash
                    }

                    // Handle metadata for background color
                    if let backgroundColor = json[.backgroundColor] as? String {
                        nft.backgroundColor = backgroundColor
                    }

                    // Additional metadata
                    if let medium = json[.medium] as? String {
                        nft.medium = medium
                    }

                    if let metadataVersion = json[.metadataVersion] as? String {
                        nft.metadataVersion = metadataVersion
                    }

                    if let symbols = json[.symbols] as? String {
                        nft.symbols = symbols
                    }

                    if let seed = json[.seed] as? String {
                        nft.seed = seed
                    }

                    if let original = json[.original] as? String {
                        nft.original = original
                    }

                    if let agreement = json[.agreement] as? String {
                        nft.agreement = agreement
                    }

                    if let website = json[.website] as? String {
                        nft.website = website
                    }

                    if let payoutAddress = json[.payoutAddress] as? String {
                        nft.payoutAddress = payoutAddress
                    }

                    if let scriptType = json[.scriptType] as? String {
                        nft.scriptType = scriptType
                    }

                    if let engineType = json[.engineType] as? String {
                        nft.engineType = engineType
                    }

                    if let accessArtworkFiles = json[.accessArtworkFiles] as? String {
                        nft.accessArtworkFiles = accessArtworkFiles
                    }

                    // Handle numeric properties
                    if let sellerFeeBasisPoints = json[.sellerFeeBasisPoints] as? Int {
                        nft.sellerFeeBasisPoints = sellerFeeBasisPoints
                    }

                    if let minted = json[.minted] as? Int {
                        nft.minted = minted
                    }

                    if let isStatic = json[.isStatic] as? Int {
                        nft.isStatic = isStatic
                    }

                    if let aspectRatio = json[.aspectRatio] as? Double {
                        nft.aspectRatio = aspectRatio
                    }

                    // Complex data structures
//                    if let platform = json[.platform] as? [String: Any] {
//                        nft.platform = platform
//                    }

//                    if let copyright = json[.copyright] as? [String: Any] {
//                        nft.copyright = copyright
//                    }

//                    if let license = json[.license] as? [String: Any] {
//                        nft.license = license
//                    }

//                    if let generatorUrl = json[.generatorUrl] as? [String: Any] {
//                        nft.generatorUrl = generatorUrl
//                    }

//                    if let termsOfService = json[.termsOfService] as? [String: Any] {
//                        nft.termsOfService = termsOfService
//                    }

//                    if let feeRecipient = json[.feeRecipient] as? [String: Any] {
//                        nft.feeRecipient = feeRecipient
//                    }

//                    if let royalties = json[.royalties] as? [String: Any] {
//                        nft.royalties = royalties
//                    }

//                    if let royaltyInfo = json[.royaltyInfo] as? [String: Any] {
//                        nft.royaltyInfo = royaltyInfo
//                    }

//                    if let properties = json[.properties] as? [String: Any] {
//                        nft.properties = properties
//                    }

//                    if let exhibitionInfo = json[.exhibitionInfo] as? [String: Any] {
//                        nft.exhibitionInfo = exhibitionInfo
//                    }

//                    if let features = json[.features] as? [String: Any] {
//                        nft.features = features
//                    }

                    // Handle traits/attributes
//                    if let attributesArray = json["attributes"] as? [[String: Any]] {
//                        var traits: [NFTTrait] = []
//
//                        for attribute in attributesArray {
//                            if let traitType = attribute["trait_type"] as? String,
//                               let value = attribute["value"] {
//                                let trait = NFTTrait(type: traitType, value: String(describing: value))
//                                traits.append(trait)
//                            }
//                        }
//
//                        nft.traits = traits
//                    } else if let traitsArray = json["traits"] as? [[String: String]] {
//                        var traits: [NFTTrait] = []
//
//                        for trait in traitsArray {
//                            if let type = trait["type"], let value = trait["value"] {
//                                let nftTrait = NFTTrait(type: type, value: value)
//                                traits.append(nftTrait)
//                            }
//                        }
//
//                        nft.traits = traits
//                    }
//    var attributes: [WalletNFTResponse.NFT.Attribute] {
//        var attributes: [WalletNFTResponse.NFT.Attribute] = []
//        if let attributeArray = data[.attributes] as? [[String: Any]] {
//            attributes = attributeArray.compactMap { dict in
//                if let traitType = dict["trait_type"] as? String, let value = dict["value"] as? String {
//                    return WalletNFTResponse.NFT.Attribute(traitType: traitType, value: value)
//                }
//                return nil
//            }
//        }
//        return attributes
//    }


                    // Save the changes
                    try modelContext.save()
                } catch {
                    print("Error updating NFT in SwiftData: \(error)")
                }
            }
        } catch {
            // The URL was not a JSON endpoint
            print("Error parsing JSON: \(error)")

            guard let content = String(data: data, encoding: .utf8) else {
                return
            }

            if content.contains("<html>") {
                // TODO: mark NFT content as website
                await MainActor.run {
                    do {
                        let descriptor = FetchDescriptor<NFT>(predicate: #Predicate { return $0.id == nftID })
                        guard let fetchedNFTs = try? modelContext.fetch(descriptor), let nft = fetchedNFTs.first else {
                            return
                        }

                        nft.contentType = "website"
                        try modelContext.save()
                    } catch {
                        print("Error updating NFT content type: \(error)")
                    }
                }
            } else {
                print(String(data: data, encoding: .utf8) ?? "Invalid UTF-8 data")
            }
        }
    }

    // Helper function to ensure URLs are secure
    private func ensureSecureURL(_ url: URL) -> URL? {
        if url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            return components.url
        } else if url.isIPFS, let ipfsURL = url.ipfsHTML {
            return ipfsURL
        }
        return url
    }

    // Handle network errors
    private func handleNetworkError(_ nsError: NSError) async {
        switch nsError.code {
        case -1003: // Server can't be reached
            // Uncomment if needed: print("Server can't be reached")
            break
        case -1001: // Timeout
            // Uncomment if needed: print("Connection timed out")
            break
        default:
            print(nsError)
        }
    }
}
