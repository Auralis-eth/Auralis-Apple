import Foundation

/// WalletConnect v2 Sign protocol wire types and relay tags.
///
/// Field names and tag numbers mirror the reference implementation
/// (reown-swift `WalletConnectSign`). Chains are CAIP-2 strings, accounts are
/// CAIP-10 strings; request params are carried as `WalletJSONValue`.
enum WalletConnectSignTag {
    static let sessionPropose = 1100
    static let sessionProposeResponseApprove = 1101
    static let sessionProposeResponseReject = 1120
    static let sessionSettle = 1102
    static let sessionSettleResponse = 1103
    static let sessionRequest = 1108
    static let sessionRequestResponse = 1109
    static let sessionEvent = 1110
    static let sessionDelete = 1112
    static let sessionDeleteResponse = 1113
    static let sessionPing = 1114
}

enum WalletConnectSignMethod {
    static let propose = "wc_sessionPropose"
    static let settle = "wc_sessionSettle"
    static let request = "wc_sessionRequest"
    static let event = "wc_sessionEvent"
    static let delete = "wc_sessionDelete"
    static let ping = "wc_sessionPing"
}

struct WCRelayProtocolOptions: Codable, Equatable {
    let `protocol`: String
    let data: String?

    init(protocol: String = "irn", data: String? = nil) {
        self.protocol = `protocol`
        self.data = data
    }
}

struct WCAppMetadata: Codable, Equatable {
    struct Redirect: Codable, Equatable {
        let native: String?
        let universal: String?
        let linkMode: Bool?
    }

    let name: String
    let description: String
    let url: String
    let icons: [String]
    let redirect: Redirect?

    init(metadata: WalletConnectionMetadata) {
        self.name = metadata.appName
        self.description = metadata.appDescription
        self.url = metadata.appURL.absoluteString
        self.icons = metadata.iconURL.map { [$0.absoluteString] } ?? []
        if let redirect = metadata.redirect {
            self.redirect = Redirect(native: redirect.native, universal: redirect.universal, linkMode: redirect.linkMode)
        } else {
            self.redirect = nil
        }
    }
}

struct WCParticipant: Codable, Equatable {
    let publicKey: String
    let metadata: WCAppMetadata
}

struct WCProposalNamespace: Codable, Equatable {
    let chains: [String]?
    let methods: [String]
    let events: [String]
}

struct WCSessionNamespace: Codable, Equatable {
    let chains: [String]?
    let accounts: [String]
    let methods: [String]
    let events: [String]
}

struct WCSessionProposal: Codable, Equatable {
    let relays: [WCRelayProtocolOptions]
    let proposer: WCParticipant
    let requiredNamespaces: [String: WCProposalNamespace]
    let optionalNamespaces: [String: WCProposalNamespace]?
    let expiryTimestamp: UInt64?
}

struct WCProposeResponse: Codable, Equatable {
    let relay: WCRelayProtocolOptions
    let responderPublicKey: String
}

struct WCSettleParams: Codable, Equatable {
    let relay: WCRelayProtocolOptions
    let controller: WCParticipant
    let namespaces: [String: WCSessionNamespace]
    let sessionProperties: [String: String]?
    let expiry: Int64
}

struct WCReason: Codable, Equatable {
    let code: Int
    let message: String

    /// Standard "user disconnected" reason (CAIP-25 / WalletConnect).
    static let userDisconnected = WCReason(code: 6000, message: "User disconnected.")
}

struct WCRequestParams: Codable, Equatable {
    struct Request: Codable, Equatable {
        let method: String
        let params: WalletJSONValue
        let expiryTimestamp: UInt64?
    }

    let request: Request
    let chainId: String
}

/// A decoded inbound relay payload: either a peer request (`method` set) or a
/// response to one of our requests (`id` + `result`/`error`).
struct WalletConnectRPCEnvelope: Decodable {
    struct Failure: Decodable, Hashable {
        let code: Int
        let message: String
    }

    let id: Int64?
    let method: String?
    let params: WalletJSONValue?
    let result: WalletJSONValue?
    let error: Failure?
}

extension WalletConnectSignTag {
    static func ttl(for tag: Int) -> Int {
        switch tag {
        case sessionPropose, sessionProposeResponseApprove, sessionSettle, sessionSettleResponse:
            return 300
        case sessionRequest, sessionRequestResponse:
            return 300
        case sessionDelete, sessionDeleteResponse:
            return 86_400
        default:
            return 300
        }
    }
}

extension WalletJSONValue {
    /// Re-decodes a JSON value into a typed `Decodable` by round-tripping JSON.
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: jsonObject ?? NSNull())
        return try JSONDecoder().decode(T.self, from: data)
    }
}
