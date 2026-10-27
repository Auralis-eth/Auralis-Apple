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
        // The symmetric key must be lowercase-or-uppercase hex of even length.
        // WalletConnect v2 uses a 32-byte (64 hex character) key; we reject any
        // non-hex/odd-length value here so malformed pairing URIs never reach the
        // transport. Full 32-byte length enforcement is deferred to the live
        // transport so this value type stays usable for shorter test fixtures.
        guard let symKey = items["symKey"], Self.isValidSymKey(symKey) else { return nil }
        self.init(
            topic: topic,
            symKey: symKey,
            relayProtocol: items["relay-protocol"] ?? "irn",
            relayData: items["relay-data"],
            expiryTimestamp: items["expiryTimestamp"].flatMap(Int64.init) ?? 0,
            methods: items["methods"].map(Self.parseMethods),
            version: version
        )
    }

    /// Parses an **externally-sourced** pairing URI (e.g. a scanned QR code or a
    /// URI pasted by the user) and rejects anything that is not a canonical
    /// WalletConnect v2 pairing — in particular a truncated/malformed symmetric
    /// key. Use this (not `init?(absoluteString:)`) whenever the URI comes from
    /// outside the app, so a bad key never reaches key derivation.
    public init?(externalScannedString: String) {
        self.init(absoluteString: externalScannedString)
        guard isCanonicalV2 else { return nil }
    }

    public var absoluteString: String {
        var parts = [
            "symKey=\(symKey)",
            "relay-protocol=\(relayProtocol)",
            "expiryTimestamp=\(expiryTimestamp)",
        ]
        if let relayData {
            // Percent-encode so a value containing reserved characters (`&`, `=`)
            // cannot corrupt the query on re-parse; the parser percent-decodes.
            parts.append("relay-data=\(relayData.walletConnectPercentEncoded)")
        }
        if let methods, !methods.isEmpty {
            // ERC-1328 encodes methods as bracket-grouped arrays, e.g. `methods=[a,b]`.
            parts.append("methods=[\(methods.joined(separator: ","))]")
        }
        return "wc:\(topic)@\(version)?\(parts.joined(separator: "&"))"
    }

    public var deeplinkURIValue: String {
        absoluteString.walletConnectPercentEncoded
    }

    /// `true` when this URI carries a full 32-byte (64 hex character) symmetric
    /// key and a 32-byte (64 hex character) topic — a canonical WalletConnect v2
    /// pairing.
    ///
    /// `init?(absoluteString:)` deliberately accepts shorter even-length hex
    /// keys and an unconstrained topic so the value type round-trips and stays
    /// usable for test fixtures, so length is *not* enforced at parse time. A live
    /// transport that ingests an externally-scanned URI should gate on this before
    /// attempting to pair, so a truncated/malformed key or topic never reaches key
    /// derivation.
    public var isCanonicalV2: Bool {
        topic.count == 64
            && topic.allSatisfy(\.isHexDigit)
            && symKey.count == 64
            && symKey.allSatisfy(\.isHexDigit)
    }

    /// Flattens ERC-1328 bracket-grouped method arrays (`[a,b],[c]`) into a flat
    /// list, tolerating the unbracketed legacy form as well.
    private static func parseMethods(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "," || $0 == "[" || $0 == "]" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func isValidSymKey(_ symKey: String) -> Bool {
        !symKey.isEmpty
            && symKey.count.isMultiple(of: 2)
            && symKey.allSatisfy(\.isHexDigit)
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

