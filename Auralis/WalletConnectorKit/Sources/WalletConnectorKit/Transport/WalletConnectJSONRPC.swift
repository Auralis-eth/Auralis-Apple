import Foundation

struct WalletConnectJSONRPCRequest<Params: Encodable>: Encodable {
    let id: Int64
    let jsonrpc: String
    let method: String
    let params: Params

    init(id: Int64, method: String, params: Params, jsonrpc: String = "2.0") {
        self.id = id
        self.jsonrpc = jsonrpc
        self.method = method
        self.params = params
    }
}

struct WalletConnectJSONRPCResponse<Result: Decodable>: Decodable {
    struct Failure: Decodable, Error, Hashable {
        let code: Int
        let message: String
    }

    let id: Int64
    let jsonrpc: String?
    let result: Result?
    let error: Failure?
}

struct WalletConnectEmptyResult: Codable, Hashable, Sendable {}

enum WalletConnectJSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()
}
