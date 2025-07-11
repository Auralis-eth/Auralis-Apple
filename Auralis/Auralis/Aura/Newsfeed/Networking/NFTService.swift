import Foundation
import SwiftData



//================================================================================================================
//================================================================================================================

// MARK: - Circuit Breaker
actor CircuitBreaker {
    private let failureThreshold: Int
    private let resetTimeout: TimeInterval
    private let halfOpenMaxCalls: Int

    private var failureCount = 0
    private var lastFailureTime: Date?
    private var state: State = .closed
    private var halfOpenCalls = 0

    enum State {
        case closed, open, halfOpen
    }

    init(failureThreshold: Int = 5, resetTimeout: TimeInterval = 60, halfOpenMaxCalls: Int = 3) {
        self.failureThreshold = failureThreshold
        self.resetTimeout = resetTimeout
        self.halfOpenMaxCalls = halfOpenMaxCalls
    }

    func canExecute() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            if let lastFailure = lastFailureTime, Date().timeIntervalSince(lastFailure) > resetTimeout {
                state = .halfOpen
                halfOpenCalls = 0
                return true
            }
            return false
        case .halfOpen:
            if halfOpenCalls < halfOpenMaxCalls {
               halfOpenCalls += 1
               return true
            }
            return false
        }
    }

    func recordSuccess() {
        failureCount = 0
        state = .closed
        halfOpenCalls = 0
    }

    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()

        if state == .halfOpen || failureCount >= failureThreshold {
            state = .open
            halfOpenCalls = 0  // Reset counter
        }
    }
}
//================================================================================================================
// MARK: - Helper Classes
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(initialPermits: Int = 1) {
        self.permits = initialPermits
    }

    func wait() async {
        if permits > 0 {
            permits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            permits += 1
        }
    }
}

//================================================================================================================
// MARK: - Optimized NFT Service
@Observable
class NFTService {
    private let nftFetcher = NFTFetcher()
    private let circuitBreaker = CircuitBreaker()

    // Rate limiting
    private let rateLimiter = AsyncSemaphore()
    private var isProcessing = false

    var isLoading: Bool { nftFetcher.loading }
    var itemsLoaded: Int? { nftFetcher.itemsLoaded }
    var total: Int? { nftFetcher.total }
    var error: Error? { nftFetcher.error }

    func fetchAllNFTs(for accountAddress: String, chain: Chain, modelContext: ModelContext) async {
        do {
            let nfts = try await nftFetcher.fetchAllNFTs(for: accountAddress, chain: chain)

            guard let nfts else {
                return
            }

            // Insert new NFTs
            await MainActor.run {
                for nft in nfts {
                    modelContext.insert(nft)
                }

                do {
                    try modelContext.save()
                } catch {
                    nftFetcher.error = error
                }
            }

            // Process NFTs with priority and concurrency control
            try await withThrowingTaskGroup(of: Void.self) { group in
                for nft in nfts {
                    group.addTask {
                        do {
                            try await self.processNFTItem(
                                nft: nft,
                                tokenURIs: Set([nft.tokenUri, nft.raw?.tokenUri].compactMap(\.self)),
                                modelContext: modelContext
                            )
                        } catch {
                            print("Failed to process NFT \(nft.id): \(error)")
                        }
                    }
                }

                // Wait for all tasks to complete
                for try await _ in group { }
            }

            // Clean up old NFTs
            await cleanupOldNFTs(currentNFTIDs: nfts.map(\.id), modelContext: modelContext)

        } catch {
            await MainActor.run {
                nftFetcher.error = error
            }
        }

        await MainActor.run {
            nftFetcher.reset()
        }
    }

    private func processNFTItem(nft: NFT, tokenURIs: Set<String>, modelContext: ModelContext) async throws {
        // Process each unique token URI
        for tokenURI in tokenURIs {
            await rateLimiter.wait()
            await parseNFTMetadata(nft: nft, tokenURI: tokenURI, modelContext: modelContext)
            await rateLimiter.signal()
        }
    }

    private func parseNFTMetadata(nft: NFT, tokenURI: String, modelContext: ModelContext) async {
        // Check if we already have metadata for this NFT
        guard await !hasMetadataForNFT(tokenURI: tokenURI, modelContext: modelContext) else {
            return
        }

        // Handle base64 JSON token URI
        if let decodedTokenURI = tokenURI.base64JSON {
            await processBase64TokenURI(decodedTokenURI, for: nft, modelContext: modelContext)
            return
        }

        // Handle URL-based token URI
        guard let url = URL(string: tokenURI) else { return }

        do {
            let metadata = try await self.fetchMetadataWithCircuitBreaker(url: url, tokenURI: tokenURI) ?? [:]
            await updateNFTWithMetadata(nft: nft, metadata: metadata, modelContext: modelContext)
        } catch {
            print("Failed to fetch metadata for \(tokenURI): \(error)")
        }
    }

    private func hasMetadataForNFT(tokenURI: String, modelContext: ModelContext) async -> Bool {
        return await MainActor.run {
            do {
                let descriptor = FetchDescriptor<NFT>(
                    predicate: #Predicate<NFT> {
                        $0.tokenUri == tokenURI &&
                        ($0.name != nil || $0.nftDescription != nil || $0.timeLastUpdated != nil)
                    }
                )

                let fetchedNFTs = try modelContext.fetch(descriptor)

                guard let fetchedNFT = fetchedNFTs.first else {
                    return false
                }

                // Check if essential metadata fields are populated
                return fetchedNFT.hasMetaData
            } catch {
                return false
            }
        }
    }

    private func fetchMetadataWithCircuitBreaker(url: URL, tokenURI: String) async throws -> [String: Any]? {
        guard await circuitBreaker.canExecute() else {
            throw NSError(domain: "CircuitBreakerOpen", code: -1, userInfo: [NSLocalizedDescriptionKey: "Circuit breaker is open"])
        }

        do {
            let metadata = try await withRetry(url: url, tokenURI: tokenURI)
            await circuitBreaker.recordSuccess()
            return metadata
        } catch {
            await circuitBreaker.recordFailure()
            throw error
        }
    }

    private func fetchMetadata(url: URL, tokenURI: String) async throws -> [String: Any]? {
        // Normalize URL
        let normalizedURL = await normalizeURL(from: url, originalTokenURI: tokenURI)

        guard let secureURL = normalizedURL, secureURL.scheme == "https" else {
            throw NSError(domain: "InvalidURL", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid or insecure URL"])
        }

        let (data, _) = try await URLSession.shared.data(from: secureURL)

        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw NSError(domain: "InvalidJSON", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON data"])
        }

        return json
    }

    private func normalizeURL(from url: URL, originalTokenURI: String) async -> URL? {
        if url.isIPFS, let ipfsHTML = url.ipfsHTML {
            return ipfsHTML
        } else if url.scheme == "ar",
                  let arWeaveURLString = try? ArweaveURLConverter.convertURL(originalTokenURI),
                  let arWeaveURL = URL(string: arWeaveURLString) {
            return arWeaveURL
        } else if url.scheme?.lowercased() == "http",
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            return components.url ?? url
        } else if url.scheme != "https" {
            return nil
        }

        return url
    }

    private func updateNFTWithMetadata(nft: NFT, metadata: [String: Any], modelContext: ModelContext) async {
        await MainActor.run {
            do {
                let descriptor = FetchDescriptor<NFT>(predicate: #Predicate { return $0.id == nft.id })
                guard let fetchedNFTs = try? modelContext.fetch(descriptor), let fetchedNFT = fetchedNFTs.first else {
                    return
                }

                // Apply all the metadata updates from your original code
                updateNFTProperties(fetchedNFT, with: metadata)

                try modelContext.save()
            } catch {
                print("Error updating NFT with metadata: \(error)")
            }
        }
    }

    private func updateNFTProperties(_ nft: NFT, with json: [String: Any]) {
        // Basic Information
        if let name = json["name"] as? String {
            nft.name = name
        } else if let artworkName = json["artworkName"] as? String {
            nft.name = artworkName
        }

        if let description = json["description"] as? String {
            nft.nftDescription = description
        }

        // Collection Information
        if let collection = json["collection"] as? [String: Any], let collectionName = collection["name"] as? String {
            nft.collectionName = collectionName
        } else if let collectionName = json["collectionName"] as? String {
            nft.collectionName = collectionName
        }

        // Additional Collection Information
        if let collectionID = json["collectionID"] as? String {
            nft.collectionID = collectionID
        }

        if let projectID = json["projectID"] as? String {
            nft.projectID = projectID
        }

        if let series = json["series"] as? String {
            nft.series = series
        }

        if let seriesID = json["seriesID"] as? String {
            nft.seriesID = seriesID
        }

        // Artist/Creator Information
        if let artistName = json["artist_name"] as? String {
            nft.artistName = artistName
        } else if let artist = json["artist"] as? String {
            nft.artistName = artist
        } else if let creator = json["creator"] as? String {
            nft.artistName = creator
        } else if let createdBy = json["createdBy"] as? String {
            nft.artistName = createdBy
        }

        // Additional Artist Information
        if let artistWebsite = json["artistWebsite"] as? String {
            nft.artistWebsite = artistWebsite
        }

    //    if let artistRoyalty = json["artistRoyalty"] as? [String: Any] {
    //        nft.artistRoyalty = artistRoyalty
    //    }

        // Media URLs
        // First handle image URLs
        if let imageURLString = json["image"] as? String {
            nft.image?.originalUrl = imageURLString
            if let imageURL = URL(string: imageURLString) {
                nft.image?.secureUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        if let imageURLString = json["imageUrl"] as? String {
            nft.image?.originalUrl = imageURLString
            if let imageURL = URL(string: imageURLString) {
                nft.image?.secureUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle primary asset URLs
        if let primaryAssetUrl = json["primaryAssetUrl"] as? String {
            nft.primaryAssetUrl = primaryAssetUrl
            if let imageURL = URL(string: primaryAssetUrl) {
                nft.securePrimaryAssetUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle preview asset URLs
        if let previewAssetUrl = json["previewAssetUrl"] as? String {
            nft.previewAssetUrl = previewAssetUrl
            if let imageURL = URL(string: previewAssetUrl) {
                nft.securePreviewAssetUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle image data
        if let imageDataUrl = json["imageData"] as? String {
            nft.imageDataUrl = imageDataUrl
            if let imageURL = URL(string: imageDataUrl) {
                nft.secureImageDataUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle high-resolution image
        if let imageHrUrl = json["imageHrUrl"] as? String {
            nft.imageHrUrl = imageHrUrl
            if let imageURL = URL(string: imageHrUrl) {
                nft.secureImageHrUrl = ensureSecureURL(imageURL)?.absoluteString
            }
        }

        // Handle image hash and details
        if let imageHash = json["imageHash"] as? String {
            nft.imageHash = imageHash
        }

    //    if let imageDetails = json["imageDetails"] as? [String: Any] {
    //        nft.imageDetails = imageDetails
    //    }

        // Then handle animation URLs
        if let animationURLString = json["animationUrl"] as? String, let animationURL = URL(string: animationURLString) {
            nft.animationUrl = animationURLString
            nft.secureAnimationUrl = ensureSecureURL(animationURL)?.absoluteString
        } else if let animationURLString = json["animation"] as? String, let animationURL = URL(string: animationURLString) {
            nft.animationUrl = animationURLString
            nft.secureAnimationUrl = ensureSecureURL(animationURL)?.absoluteString
        }

        // Handle animation details
    //    if let animationDetails = json["animationDetails"] as? [String: Any] {
    //        nft.animationDetails = animationDetails
    //    }

        // Handle audio URLs
        if let audioURLString = json["audioUrl"] as? String {
            nft.audioUrl = audioURLString
        } else if let audioURLString = json["audioURI"] as? String {
            nft.audioUrl = audioURLString
        } else if let audioURLString = json["audio"] as? String {
            nft.audioUrl = audioURLString
        } else if let audioURLString = json["losslessAudio"] as? String {
            nft.audioUrl = audioURLString
        }

        // Handle external URLs/links
        if let externalURLString = json["externalUrl"] as? String {
            nft.externalUrl = externalURLString
        } else if let externalURLString = json["external_link"] as? String {
            nft.externalUrl = externalURLString
        } else if let externals = json["externalUrl"] as? [String: Any],
                  let externalURLString = externals["url"] as? String {
            nft.externalUrl = externalURLString
        }

        // Handle 3D model URLs
        if let modelURLString = json["modelGlb"] as? String {
            nft.modelUrl = modelURLString
        } else if let modelURLString = json["vrmUrl"] as? String {
            nft.modelUrl = modelURLString
        } else if let modelURLString = json["usdzUrl"] as? String {
            nft.modelUrl = modelURLString
        } else if let modelURLString = json["print3DSTL"] as? String {
            nft.modelUrl = modelURLString
        }

        // Handle token IDs
        if let tokenID = json["tokenID"] as? Int {
            nft.tokenId = String(tokenID)
        } else if let tokenID = json["tokenId"] as? Int {
            nft.tokenId = String(tokenID)
        } else if let tokenIDString = json["tokenID"] as? String {
            nft.tokenId = tokenIDString
        } else if let tokenIDString = json["tokenId"] as? String {
            nft.tokenId = tokenIDString
        }

        // Handle unique ID
        if let uniqueID = json["id"] as? String {
            nft.uniqueID = uniqueID
        }

        // Handle timestamp and token hash
        if let timestamp = json["timestamp"] as? String {
            nft.timestamp = timestamp
        }

        if let tokenHash = json["tokenHash"] as? String {
            nft.tokenHash = tokenHash
        }

        // Handle metadata for background color
        if let backgroundColor = json["backgroundColor"] as? String {
            nft.backgroundColor = backgroundColor
        }

        // Additional metadata
        if let medium = json["medium"] as? String {
            nft.medium = medium
        }

        if let metadataVersion = json["metadataVersion"] as? String {
            nft.metadataVersion = metadataVersion
        }

        if let symbols = json["symbols"] as? String {
            nft.symbols = symbols
        }

        if let seed = json["seed"] as? String {
            nft.seed = seed
        }

        if let original = json["original"] as? String {
            nft.original = original
        }

        if let agreement = json["agreement"] as? String {
            nft.agreement = agreement
        }

        if let website = json["website"] as? String {
            nft.website = website
        }

        if let payoutAddress = json["payoutAddress"] as? String {
            nft.payoutAddress = payoutAddress
        }

        if let scriptType = json["scriptType"] as? String {
            nft.scriptType = scriptType
        }

        if let engineType = json["engineType"] as? String {
            nft.engineType = engineType
        }

        if let accessArtworkFiles = json["accessArtworkFiles"] as? String {
            nft.accessArtworkFiles = accessArtworkFiles
        }

        // Handle numeric properties
        if let sellerFeeBasisPoints = json["sellerFeeBasisPoints"] as? Int {
            nft.sellerFeeBasisPoints = sellerFeeBasisPoints
        }

        if let minted = json["minted"] as? Int {
            nft.minted = minted
        }

        if let isStatic = json["isStatic"] as? Int {
            nft.isStatic = isStatic
        }

        if let aspectRatio = json["aspectRatio"] as? Double {
            nft.aspectRatio = aspectRatio
        }

        // Complex data structures (commented out as in original)
    //    if let platform = json["platform"] as? [String: Any] {
    //        nft.platform = platform
    //    }

    //    if let copyright = json["copyright"] as? [String: Any] {
    //        nft.copyright = copyright
    //    }

    //    if let license = json["license"] as? [String: Any] {
    //        nft.license = license
    //    }

    //    if let generatorUrl = json["generatorUrl"] as? [String: Any] {
    //        nft.generatorUrl = generatorUrl
    //    }

    //    if let termsOfService = json["termsOfService"] as? [String: Any] {
    //        nft.termsOfService = termsOfService
    //    }

    //    if let feeRecipient = json["feeRecipient"] as? [String: Any] {
    //        nft.feeRecipient = feeRecipient
    //    }

    //    if let royalties = json["royalties"] as? [String: Any] {
    //        nft.royalties = royalties
    //    }

    //    if let royaltyInfo = json["royaltyInfo"] as? [String: Any] {
    //        nft.royaltyInfo = royaltyInfo
    //    }

    //    if let properties = json["properties"] as? [String: Any] {
    //        nft.properties = properties
    //    }

    //    if let exhibitionInfo = json["exhibitionInfo"] as? [String: Any] {
    //        nft.exhibitionInfo = exhibitionInfo
    //    }

    //    if let features = json["features"] as? [String: Any] {
    //        nft.features = features
    //    }

        // Handle traits/attributes (commented out as in original)
    //    if let attributesArray = json["attributes"] as? [[String: Any]] {
    //        var traits: [NFTTrait] = []
    //
    //        for attribute in attributesArray {
    //            if let traitType = attribute["trait_type"] as? String,
    //               let value = attribute["value"] {
    //                let trait = NFTTrait(type: traitType, value: String(describing: value))
    //                traits.append(trait)
    //            }
    //        }
    //
    //        nft.traits = traits
    //    } else if let traitsArray = json["traits"] as? [[String: String]] {
    //        var traits: [NFTTrait] = []
    //
    //        for trait in traitsArray {
    //            if let type = trait["type"], let value = trait["value"] {
    //                let nftTrait = NFTTrait(type: type, value: value)
    //                traits.append(nftTrait)
    //            }
    //        }
    //
    //        nft.traits = traits
    //    }
    }

    private func ensureSecureURL(_ url: URL) -> URL? {
        if url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            return components.url
        } else if url.isIPFS, let ipfsURL = url.ipfsHTML {
            return ipfsURL
        }
        return url
    }

    private func processBase64TokenURI(_ decodedURI: [String: Any], for nft: NFT, modelContext: ModelContext) async {
        await updateNFTWithMetadata(nft: nft, metadata: decodedURI, modelContext: modelContext)
    }

    private func cleanupOldNFTs(currentNFTIDs: [String], modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { !currentNFTIDs.contains($0.id) }
        )

        await MainActor.run {
            do {
                try modelContext.enumerate(descriptor) { nft in
                    modelContext.delete(nft)
                }
                try modelContext.save()
            } catch {
                print("Failed to cleanup old NFTs from SwiftData: \(error)")
                nftFetcher.error = error
            }
        }
    }

    func refreshNFTs(for currentAccount: EOAccount?, chain: Chain, modelContext: ModelContext) async {
        guard let accountAddress = currentAccount?.address else {
            return
        }

        await fetchAllNFTs(
            for: accountAddress,
            chain: chain,
            modelContext: modelContext
        )
    }

    func reset() {
        nftFetcher.reset()
    }

    func withRetry(url: URL, tokenURI: String) async throws -> [String : Any]? {

        let maxAttempts: Int = 3
        let maxDelay: TimeInterval = 30.0
        let backoffMultiplier: Double = 2.0

        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                return try await self.fetchMetadata(url: url, tokenURI: tokenURI)
            } catch {
                lastError = error

                if attempt < maxAttempts - 1 {
                    let delay = min(
                        pow(backoffMultiplier, Double(attempt)),
                        maxDelay
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NSError(domain: "RetryError", code: -1, userInfo: [NSLocalizedDescriptionKey: "All retry attempts failed"])
    }
}

