import Foundation

public struct WalletConnectURI: Hashable, Codable, Sendable {
    public let topic: String
    public let version: String
    public let symKey: String
    public let relayProtocol: String
    public let relayData: String?
    public let expiryTimestamp: Int64
    public let methods: [String]?

    public init(
        topic: String,
        symKey: String,
        relayProtocol: String = "irn",
        relayData: String? = nil,
        expiryTimestamp: Int64,
        methods: [String]? = nil,
        version: String = "2"
    ) {
        self.topic = topic
        self.version = version
        self.symKey = symKey
        self.relayProtocol = relayProtocol
        self.relayData = relayData
        self.expiryTimestamp = expiryTimestamp
        self.methods = methods
    }

    public init?(absoluteString: String) {
        guard absoluteString.hasPrefix("wc:"),
              let atIndex = absoluteString.firstIndex(of: "@"),
              let questionIndex = absoluteString.firstIndex(of: "?"),
              atIndex < questionIndex else {
            return nil
        }

        let topicStart = absoluteString.index(absoluteString.startIndex, offsetBy: 3)
        let topic = String(absoluteString[topicStart..<atIndex])
        let versionStart = absoluteString.index(after: atIndex)
        let version = String(absoluteString[versionStart..<questionIndex])
        let queryStart = absoluteString.index(after: questionIndex)
        let query = String(absoluteString[queryStart...])
        guard !topic.isEmpty, !version.isEmpty else { return nil }

        let items = Self.queryItems(from: query)
        guard let symKey = items["symKey"], !symKey.isEmpty else { return nil }
        self.init(
            topic: topic,
            symKey: symKey,
            relayProtocol: items["relay-protocol"] ?? "irn",
            relayData: items["relay-data"],
            expiryTimestamp: items["expiryTimestamp"].flatMap(Int64.init) ?? 0,
            methods: items["methods"].map { $0.split(separator: ",").map(String.init) },
            version: version
        )
    }

    public var absoluteString: String {
        var parts = [
            "symKey=\(symKey)",
            "relay-protocol=\(relayProtocol)",
            "expiryTimestamp=\(expiryTimestamp)",
        ]
        if let relayData {
            parts.append("relay-data=\(relayData)")
        }
        if let methods, !methods.isEmpty {
            parts.append("methods=\(methods.joined(separator: ","))")
        }
        return "wc:\(topic)@\(version)?\(parts.joined(separator: "&"))"
    }

    public var deeplinkURIValue: String {
        absoluteString.walletConnectPercentEncoded
    }

    private static func queryItems(from query: String) -> [String: String] {
        query
            .split(separator: "&")
            .reduce(into: [:]) { result, item in
                let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let name = parts.first else { return }
                result[String(name)] = parts.dropFirst().first.map(String.init)?.removingPercentEncoding
            }
    }
}

extension String {
    var walletConnectPercentEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .walletConnectNestedURIAllowed) ?? self
    }
}

private extension CharacterSet {
    static let walletConnectNestedURIAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}

