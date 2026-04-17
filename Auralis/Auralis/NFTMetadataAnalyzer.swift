//
//  NFTMetadataAnalyzer.swift
//  Auralis
//
//  Extracted from AuralisApp.swift on request.
//

import Foundation
import OSLog
import SwiftData

private let metadataAnalysisLogger = Logger(subsystem: "Auralis", category: "NFTMetadataAnalyzer")

// MARK: - Metadata Analysis Models
struct MetadataKeyInfo {
    let key: String
    let dataTypes: Set<String>
    let sampleValues: [String]
    let occurrenceCount: Int

    var description: String {
        let typesString = Array(dataTypes).sorted().joined(separator: ", ")
        let samplesString = sampleValues.prefix(3).joined(separator: ", ")
        return "\(key): [\(typesString)] - Count: \(occurrenceCount) - Samples: \(samplesString)"
    }
}

struct MetadataAnalysisResult {
    let processedKeys: Set<String>
    let unprocessedKeys: [MetadataKeyInfo]
    let totalNFTsAnalyzed: Int
    let totalAddressesProcessed: Int

    func printSummary() {
        metadataAnalysisLogger.notice("=== NFT Metadata Analysis Results ===")
        metadataAnalysisLogger.notice("Total Addresses Processed: \(totalAddressesProcessed, privacy: .public)")
        metadataAnalysisLogger.notice("Total NFTs Analyzed: \(totalNFTsAnalyzed, privacy: .public)")
        metadataAnalysisLogger.notice("Unique Processed Keys: \(processedKeys.count, privacy: .public)")
        metadataAnalysisLogger.notice("Unique Unprocessed Keys: \(unprocessedKeys.count, privacy: .public)")
        metadataAnalysisLogger.notice("--- UNPROCESSED METADATA KEYS ---")
        for keyInfo in unprocessedKeys.sorted(by: { $0.occurrenceCount > $1.occurrenceCount }) {
            metadataAnalysisLogger.notice("\(keyInfo.description, privacy: .public)")
        }

        metadataAnalysisLogger.notice("--- PROCESSED KEYS (for reference) ---")
        for key in processedKeys.sorted() {
            metadataAnalysisLogger.notice("✓ \(key, privacy: .public)")
        }
    }
}

// MARK: - Main Analysis Function
@MainActor
class NFTMetadataAnalyzer {
    private let logger = metadataAnalysisLogger
    private let nftService = NFTService()

    // Keys that are currently being processed by NFTMetadataUpdater
    private let processedKeys: Set<String> = [
        // Basic Information
        "name", "artworkName", "description",

        // Collection Information
        "collection", "collectionName", "collectionID", "projectID", "series", "seriesID",

        // Artist/Creator Information
        "artist_name", "artist", "creator", "createdBy", "artistWebsite",

        // Media URLs
        "image", "imageUrl", "primaryAssetUrl", "previewAssetUrl", "imageData", "imageDataUrl",
        "imageHrUrl", "imageHash", "animation_url", "animationUrl", "animation",
        "audioUrl", "audioURI", "audio", "losslessAudio",
        "external_url", "externalUrl", "external_link",
        "modelGlb", "vrmUrl", "usdzUrl", "print3DSTL",

        // Token Information
        "tokenID", "tokenId", "id", "timestamp", "tokenHash",

        // Metadata Properties
        "background_color", "backgroundColor", "medium", "metadataVersion", "symbols",
        "seed", "original", "agreement", "website", "payoutAddress", "scriptType",
        "engineType", "accessArtworkFiles",

        // Numeric Properties
        "sellerFeeBasisPoints", "minted", "isStatic", "aspectRatio",

        // Traits/Attributes
        "attributes", "traits"
    ]

    func analyzeMetadataAcrossAddresses(
        addresses: [String],
        chain: Chain,
        modelContext: ModelContext
    ) async -> MetadataAnalysisResult {

        var allMetadataKeys: [String: MetadataKeyInfo] = [:]
        var totalNFTsAnalyzed = 0
        var successfulAddresses = 0

        logger.notice("Starting metadata analysis for \(addresses.count, privacy: .public) addresses")

        for (index, address) in addresses.enumerated() {
            logger.notice("Processing address \(index + 1, privacy: .public)/\(addresses.count, privacy: .public): \(address, privacy: .public)")

            do {
                // Fetch NFTs for this address
                let correlationID = UUID().uuidString
                await nftService.fetchAllNFTs(
                    for: address,
                    chain: chain,
                    modelContext: modelContext,
                    correlationID: correlationID
                )

                // Get NFTs from the model context
                let normalizedAccountAddress = NFT.normalizedScopeComponent(address) ?? ""
                let fetchDescriptor = FetchDescriptor<NFT>(
                    predicate: #Predicate<NFT> {
                        $0.accountAddressRawValue == normalizedAccountAddress &&
                        $0.networkRawValue == chain.rawValue
                    }
                )
                let nfts = try modelContext.fetch(fetchDescriptor)

                logger.notice("Found \(nfts.count, privacy: .public) NFTs for address \(address, privacy: .public)")

                // Analyze metadata for each NFT
                for nft in nfts {
                    if let metadata = nft.raw?.metadata {
                        analyzeMetadataKeys(metadata: metadata, allKeys: &allMetadataKeys)
                        totalNFTsAnalyzed += 1
                    }
                }

                successfulAddresses += 1

            } catch {
                logger.error("Error processing address \(address, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }

            // Small delay to be respectful to APIs
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        // Filter out processed keys to find unprocessed ones
        let unprocessedKeys = allMetadataKeys.values
            .filter { !processedKeys.contains($0.key) }
            .sorted { $0.occurrenceCount > $1.occurrenceCount }

        let result = MetadataAnalysisResult(
            processedKeys: processedKeys,
            unprocessedKeys: unprocessedKeys,
            totalNFTsAnalyzed: totalNFTsAnalyzed,
            totalAddressesProcessed: successfulAddresses
        )

        return result
    }

    private func analyzeMetadataKeys(
        metadata: [String: JSONValue],
        allKeys: inout [String: MetadataKeyInfo]
    ) {
        for (key, value) in metadata {
            let dataType = getDataType(from: value)
            let sampleValue = getSampleValue(from: value)

            if var existingKeyInfo = allKeys[key] {
                // Update existing key info
                existingKeyInfo = MetadataKeyInfo(
                    key: existingKeyInfo.key,
                    dataTypes: existingKeyInfo.dataTypes.union([dataType]),
                    sampleValues: Array(Set(existingKeyInfo.sampleValues + [sampleValue]).prefix(5)),
                    occurrenceCount: existingKeyInfo.occurrenceCount + 1
                )
                allKeys[key] = existingKeyInfo
            } else {
                // Create new key info
                allKeys[key] = MetadataKeyInfo(
                    key: key,
                    dataTypes: [dataType],
                    sampleValues: [sampleValue],
                    occurrenceCount: 1
                )
            }

            // Recursively analyze nested objects
            if case .object(let nestedDict) = value {
                analyzeNestedMetadata(
                    parentKey: key,
                    metadata: nestedDict,
                    allKeys: &allKeys
                )
            }
        }
    }

    private func analyzeNestedMetadata(
        parentKey: String,
        metadata: [String: JSONValue],
        allKeys: inout [String: MetadataKeyInfo]
    ) {
        for (nestedKey, value) in metadata {
            let fullKey = "\(parentKey).\(nestedKey)"
            let dataType = getDataType(from: value)
            let sampleValue = getSampleValue(from: value)

            if var existingKeyInfo = allKeys[fullKey] {
                existingKeyInfo = MetadataKeyInfo(
                    key: existingKeyInfo.key,
                    dataTypes: existingKeyInfo.dataTypes.union([dataType]),
                    sampleValues: Array(Set(existingKeyInfo.sampleValues + [sampleValue]).prefix(5)),
                    occurrenceCount: existingKeyInfo.occurrenceCount + 1
                )
                allKeys[fullKey] = existingKeyInfo
            } else {
                allKeys[fullKey] = MetadataKeyInfo(
                    key: fullKey,
                    dataTypes: [dataType],
                    sampleValues: [sampleValue],
                    occurrenceCount: 1
                )
            }
        }
    }

    private func getDataType(from value: JSONValue) -> String {
        switch value {
        case .string(_):
            return "String"
        case .bool(_):
            return "Bool"
        case .array(_):
            return "Array"
        case .object(_):
            return "Object"
        case .null:
            return "Null"
        case .int(_):
            return "Integer"
        case .double(_):
            return "Double"
        }
    }

    private func getSampleValue(from value: JSONValue) -> String {
        switch value {
        case .string(let str):
            return String(str.prefix(50)) + (str.count > 50 ? "..." : "")
        case .bool(let bool):
            return String(bool)
        case .array(let arr):
            return "Array[\(arr.count)]"
        case .object(let obj):
            return "Object{\(obj.keys.count) keys}"
        case .null:
            return "null"
        case .int(let value):
            return "\(value)"
        case .double(let double):
            return "\(double)"
        }
    }
}

// MARK: - Usage Example
@MainActor
func runMetadataAnalysis() async {
    let testAddresses: [String] = [
        "0xe0036fb4b5a3b232acfc01fec3bd1d787a93da75",
        "0xd5481575130a7decf4503c81a50152b3753031f9",
        "0x1236e0ffe9cf70edd7c80bdb1676bdd0ad1df0f8",
        "0xa5c8a62f221adeaf8a7c0bef60044861d9c4b400",
        "0xddce770ba87ca6efda95c9332121b8006b784a9a",
        "0xa7a3a06e9a649939f60be309831b5e0ea6cc2513",
        "0x11287fb57ace963c8e4051aff36a30a76404fe28",
        "0x96acf191c0112806f9709366bad77642b99b21a9",
        "0x2e2396c94c68e99958982371aa4fb2d642d13c19",
        "0x6e32c149094e8007d7bb838554175470ecf82f3e",
        "0x0ee01fd0bdb6b449cf343ecafa7116be49b5286a",
        "0x759c51e04dd9062e8d2071febe9d47caea199de5",
        "0xa14a7bcee81891130ed31e51aeab3a2ea5bc0675",
        "0x996e1d4ce3e1e558889832832004b2466153adbe",
        "0x88d1913043241cb0222937b6fb7b9792619a9059",
        "0xbb6a0fbe1f1d4d7d3df73efa4dc2888f6dce1736",
        "0x3839f6478a233496efda0f50081afeced2cf5817",
        "0x2c8c68f84dfe2be2908f3aa54ab8505b7347ee02",
        "0xb394f1aa30ba874df3ae6097bf4c2474b2d8f3ac",
        "0x123e68d1a76fe193c5fd1379deb01ee2600513c0",
        "0x3988e5cd9e9eafbced7e0a91db18f10307fad853",
        "0xc7d4ac32fd6a38230b4c60b2d6fc21a6cf782a39",
        "0xa697aedf5af55fd7a3d75122faa8ffc57e84261c",
        "0xc835d6a8473d4e4f6807a9192b8d90c694a2021f",
        "0x88888803cc228b1fa6afbe05d571b3ed1e3f1325",
        "0x87472dab8f6471418bf836856addda6d5a212345",
        "0x550d141abf0016f4819e7023eabd997e6aebaf1f",
        "0x5610f74cbb7a4affb09f4f5363cdf9493cc40ae4",
        "0x03035f22506f427b37629693c51df56f03400000",
        "0x40402322ecb6c61610b9ad2cf889792c5e2295b2",
        "0x5169c7a3477d6027a3897069e1f4fa1962ed8784",
        "0x912df5e88cbff848d1cbf66b53e01ed676999999",
        "0x392c517f2dccc09382f832c29440f8fb10ac8e86",
        "0x0bc1ca13a06f6D13F0b67ce451379C9468CD5e4f",
        "0xFEFDEbCe0dC6Adaf34bBc4f9968e6d290A97cbA4",
        "0x5BD977356546db1aDb54b6903862D7C2F187839B",
        "0xd83CeEB78c3b94EDa193A34C1298847AFC5B89BA",
        "0x120729a1e737E9eC8Ef56F3aFC19705cacFC2447",
        "0x838e1CE3E6F188d0f3a72F4B61ECf7956119247A",
        "0x1bCE0701F553594189BBeeD07a230Bf88A74e7a8",
        "0x53691721f640E17146Ab162aeE575c8eA3411C3D",
        "0x32A0D6B013CF8ecAd1e37e99532570411D398D05",
        "0xae8d25938D97A2a1CDaefD224aD234484F7C4394",
        "0x7008005A6bCA352f364887f63CA6a1cB647afB0C",
        "0x05aCe07b158e18CD722f829F9e8A674870577477",
        "0x5375aFA74a61C7006f4042E77D815aFd447594eD",
        "0xA46128894419058F48089e5C9eB7CF6a8a932A80",
        "0x3E5928c6d059A38BF0329694908604A0eedB0919",
        "0x3fa5A25F48BA1b736761706801be4f639cA4853e",
        "0xFE59F409d7A05f8e24aa90626186Cc820c8e3005",
        "0xe07E7dA4227Ebf6f2bfAB62A3263F54dBD49dB4A",
        "0xf3F03450B8acaD912AEE628e08E5A4a4a3ED0770",
        "0x63A65fC3a6E3714e2a210B7fE17A9d743426DA22",
        "0x4876770FF279113022b6CB4C5aEaB5F08869EB88",
        "0xd6670674977FFf91084AD224Dd36033E3C545EDB",
        "0xa003E9D948523B4e6A519F22cBdAc3617AB97f34",
        "0x4515733DA791849cD251E75Ef30c7fE55Ba17bcd",
        "0x693D6411e441088848Bf8dBf1670093b53E36bBE",
        "0xDB22139FBD5081d57ed1191fDaC5Ad990436AD44",
        "0xbAcFE2D0f7F1fD35C5c97726ea2b208fA222E620",
        "0x522BD1179dc911947124a688EDA977BDC7B40233",
        "0xF5569a9499AFa00755259cBB6C6a54B73169EcEb",
        "0x507fCf8607fD2f646B76D78378817D17C506BBB1",
        "0x144757a24B61Cee2e593ADe64DA776759D786d73"
    ]


    // You'll need to get your ModelContext instance
    let schema = Schema([NFT.self, EOAccount.self])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container: ModelContainer
    do {
        container = try ModelContainer(for: schema, configurations: [configuration])
    } catch {
        assertionFailure("Failed to create in-memory model container: \(error)")
        return
    }

    // Create the context
    let modelContext = ModelContext(container)

    let analyzer = NFTMetadataAnalyzer()

    // Example for Ethereum mainnet - adjust chain as needed
    let chain = Chain.ethMainnet // or whatever your Chain enum values are

    // Uncomment and use with your actual ModelContext

    let result = await analyzer.analyzeMetadataAcrossAddresses(
        addresses: testAddresses,
        chain: chain,
        modelContext: modelContext
    )

    result.printSummary()

    metadataAnalysisLogger.notice("Top 5 most common unprocessed keys:")
    for keyInfo in result.unprocessedKeys.prefix(5) {
        metadataAnalysisLogger.notice("- \(keyInfo.key, privacy: .public): appears \(keyInfo.occurrenceCount, privacy: .public) times")
    }

}
