import AuralisPrimaryModels
import Foundation
import OSLog

private let nftMetadataDictionaryLogger = Logger(subsystem: "Auralis", category: "NFTMetadataDictionary")

public extension Dictionary where Key == String, Value == JSONValue {

    public var image: String? {
        self["image"]?.stringValue
    }

    public var name: String? {
        self["name"]?.stringValue
    }

    public var metadataDescription: String? {
        self["description"]?.stringValue
    }

    public var attributes: [NFT.Attribute]? {
        guard case let .array(jsonArray)? = self["attributes"] else { return nil }

        return jsonArray.compactMap { value in
            guard case let .object(attrDict) = value else { return nil }
            return decodeAttribute(from: attrDict)
        }
    }

    private func decodeAttribute(from dict: [String: JSONValue]) -> NFT.Attribute? {
        do {
            let data = try JSONEncoder().encode(dict)
            return try JSONDecoder().decode(NFT.Attribute.self, from: data)
        } catch {
            nftMetadataDictionaryLogger.error("Failed to decode NFT attribute: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public var asNFTMetadata: NFT.NFTMetadata {
        NFT.NFTMetadata(
            image: self.image,
            name: self.name,
            metadataDescription: self.metadataDescription,
            attributes: self.attributes
        )
    }
}
