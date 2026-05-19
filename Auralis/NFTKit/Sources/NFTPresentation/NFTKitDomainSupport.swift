import AuralisPrimaryModels
import Foundation

extension String {
    var displayAddress: String {
        if count > 10 {
            let start = prefix(6)
            let end = suffix(4)
            return "\(start)...\(end)"
        }
        return self
    }

    var base64JSON: [String: JSONValue]? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = trimmedValue.lowercased()

        guard normalizedValue.hasPrefix("data:application/json"),
              let base64StartRange = trimmedValue.range(of: "base64,", options: .caseInsensitive) else {
            return nil
        }

        let base64String = String(trimmedValue[base64StartRange.upperBound...])
        guard let jsonData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        return try? JSONDecoder().decode([String: JSONValue].self, from: jsonData)
    }
}

extension Set where Element == String {
    func siftTokenURIs() -> Set<String> {
        var bestURIs: [String: (uri: String, priority: URIFormat)] = [:]
        var otherURIs = Set<String>()

        for uri in self where !uri.isEmpty {
            var foundMatch = false

            for config in URIConfig.uriConfigurations where uri.hasPrefix(config.prefix) {
                guard uri.count > config.prefix.count else {
                    otherURIs.insert(uri)
                    continue
                }

                let startIndex = uri.index(uri.startIndex, offsetBy: config.prefix.count)
                let remainder = String(uri[startIndex...])
                let components = remainder.split(separator: "/", maxSplits: 1)

                if components.count >= 1, !components[0].isEmpty {
                    let identifier = String(components[0])
                    let path = components.count > 1 ? String(components[1]) : ""
                    let resource = NormalizedResource(type: config.type, identifier: identifier, path: path)

                    if let existing = bestURIs[resource.canonicalForm] {
                        if config.format > existing.priority {
                            bestURIs[resource.canonicalForm] = (uri, config.format)
                        }
                    } else {
                        bestURIs[resource.canonicalForm] = (uri, config.format)
                    }

                    foundMatch = true
                    break
                }
            }

            if !foundMatch {
                otherURIs.insert(uri)
            }
        }

        var result = Set(bestURIs.values.map(\.uri))
        result.formUnion(otherURIs)
        return result
    }
}

private enum URIFormat: Int, Comparable {
    case content = 1
    case location = 2
    case optimizedLocation = 3

    static func < (lhs: URIFormat, rhs: URIFormat) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

private struct NormalizedResource {
    enum ResourceType: String {
        case arweave
        case ipfs
    }

    let type: ResourceType
    let identifier: String
    let path: String

    var canonicalForm: String {
        "\(type.rawValue):\(identifier):\(path)"
    }
}

private struct URIConfig {
    let prefix: String
    let type: NormalizedResource.ResourceType
    let format: URIFormat

    static let uriConfigurations: [URIConfig] = [
        URIConfig(prefix: "ar://", type: .arweave, format: .content),
        URIConfig(prefix: "https://arweave.net/", type: .arweave, format: .location),
        URIConfig(prefix: "ipfs://", type: .ipfs, format: .content),
        URIConfig(prefix: "https://ipfs.io/ipfs/", type: .ipfs, format: .location),
        URIConfig(prefix: "https://alchemy.mypinata.cloud/ipfs/", type: .ipfs, format: .optimizedLocation)
    ]
}

extension URL {
    static func sanitizedRemoteMediaURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let candidateURL = URL(string: trimmed) else {
            return nil
        }

        if candidateURL.scheme == "ipfs",
           let gatewayURL = candidateURL.toPinataGatewayURL(),
           gatewayURL.isSupportedRemoteMediaURL {
            return gatewayURL
        }

        guard candidateURL.isSupportedRemoteMediaURL else {
            return nil
        }

        return candidateURL
    }

    var isSupportedRemoteMediaURL: Bool {
        guard let scheme = scheme?.lowercased(),
              let host,
              !host.isEmpty else {
            return false
        }

        return scheme == "https"
    }

    func toPinataGatewayURL() -> URL? {
        guard scheme != nil, let originalHost = host, !originalHost.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "gateway.pinata.cloud"
        components.path = "/ipfs/\(originalHost)"

        if path() != "/" {
            components.path += path()
        }

        components.query = query
        components.fragment = fragment
        return components.url
    }
}
