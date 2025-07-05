//
//  MetaMaskSDK.swift
//  Fetch
//
//  Created by Daniel Bell on 6/12/25.
//


import SwiftUI
import UIKit
import Combine
import Foundation


public class MetaMaskSDK: ObservableObject {
    @Published public var chainId: String = ""
    @Published public var connected: Bool = false
    @Published public var account: String = ""
    @Published public var error: RequestError? = nil
    @Published public var urlToOpen: URL? = nil


//=============================================================
//TODO: process...do we need, can we simplify etc
    let dappScheme: String = "fetchdapp"
    public var appMetadata: AppMetadata = AppMetadata(
        name: "Fetch Dapp",
        url: "https://fetchdapp.com",
        iconUrl: "https://cdn.sstatic.net/Sites/stackoverflow/Img/apple-touch-icon.png"
    )
//=============================================================
    static let shared = MetaMaskSDK()

    public init() {}

    private var isMetaMaskInstalled: Bool {
        guard let url = URL(string: "metamask://") else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }

    public func handleUrl(_ url: URL) {

        guard url.scheme != nil else {
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }

        guard components.host == Deeplink.mmsdk else {
            return
        }

        guard let message = components.queryItems?.first(where: { $0.name == "message" })?.value else {
            return
        }

        let base64Decoded = message.base64Decode() ?? ""
        connected = true
        handleMessage(base64Decoded)
    }
}

public extension MetaMaskSDK {
    func connect() async {
        func originatorInfo() -> RequestInfo {

            var version: String {
                /// Bundle with SDK plist
                let sdkBundle: [String: Any] = Bundle(for: MetaMaskSDK.self).infoDictionary ?? [:]
                return sdkBundle["CFBundleShortVersionString"] as? String ?? ""
            }

            let originatorInfo = OriginatorInfo(
                title: appMetadata.name,
                url: appMetadata.url,
                icon: appMetadata.iconUrl ?? appMetadata.base64Icon,
                dappId: Bundle.main.bundleIdentifier,
                platform: UIDevice.current.systemName.lowercased(),
                apiVersion: appMetadata.apiVersion ?? version
            )

            return RequestInfo(
                type: "originator_info",
                originator: originatorInfo,
                originatorInfo: originatorInfo
            )
        }

        let originatorInfo = originatorInfo().toJsonString()?.base64Encode() ?? ""
        let channelId = UUID().uuidString.lowercased()
        let message = "connect?scheme=\(dappScheme)&channelId=\(channelId)&comm=deeplinking&originatorInfo=\(originatorInfo)"
        let deeplink = "metamask://\(message)"

        guard
            let urlString = deeplink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: urlString)
        else {
            return
        }

        await MainActor.run {
            urlToOpen = url
        }
    }

    func clearSession() {
        self.chainId = ""
        self.account = ""
        connected = false
    }
}

extension MetaMaskSDK {
    private func updateAccount(_ account: String) {
        self.account = account
        connected = true
    }

    public func handleMessage(_ message: String) {
        do {
            guard let data = message.data(using: .utf8) else {
                return
            }

            let json: [String: Any] = try JSONSerialization.jsonObject(
                with: data,
                options: []
            )
                as? [String: Any] ?? [:]

            guard let data = json["data"] as? [String: Any] else {
                return
            }

            if data["id"] != nil {
                if let error = data["error"] as? [String: Any] {
                    self.error = RequestError(from: error)

                    if self.error?.codeType == .unauthorisedRequest {
                        clearSession()
                    }

                    // metamask_connectSign & metamask_connectwith can have both error & result
                    // if connection is approved but rpc request is denied
                    let accounts = data["accounts"] as? [String] ?? []

                    if let account = accounts.first {
                        updateAccount(account)
                    }

                    if let chainId = data["chainId"] as? String {
                        self.chainId = chainId
                    }

                    return
                }

                if let chainId = data["chainId"] as? String {
                    self.chainId = chainId
                }

                if
                    let accounts = data["accounts"] as? [String],
                    let selectedAddress = accounts.first {
                    updateAccount(selectedAddress)
                }

                if let result = data["result"] {
                }
            } else {
                if let error = data["error"] as? [String: Any] {
                    self.error = RequestError(from: error)

                    if self.error?.codeType == .unauthorisedRequest {
                        clearSession()
                    }
                }

                if let method = data["method"] as? String,
                    EthereumMethod(rawValue: method) != .none {

                }

                if let chainId = data["chainId"] as? String {
                    self.chainId = chainId
                }

                if
                    let accounts = data["accounts"] as? [String],
                    let selectedAddress = accounts.first {
                    updateAccount(selectedAddress)
                }
            }

        } catch {
            print("DeeplinkClient:: Could not convert message to json. Message: \(message)\nError: \(error)")
        }
    }
}


public struct RequestError: Codable, Error {
    enum Kind: CaseIterable {
        case generic
        case connect
        case response
        var code: Int {
            switch self {
                case .generic:
                    return -100
                case .connect:
                    return -101
                case .response:
                    return -105
            }
        }

        var message: String {
            switch self {
                case .generic:
                    return "Something went wrong"
                case .connect:
                    return "Not connected. Please connect first"
                case .response:
                    return "Unexpected response"
            }
        }
    }
    public let code: Int
    public let message: String

    init(from info: [String: Any]) {
        code = info["code"] as? Int ?? -1
        if let msg = info["message"] as? String ?? ErrorType(rawValue: code)?.message {
            message = msg
        } else if ErrorType.isServerError(code) {
            message = ErrorType.serverError.message
        } else {
            message = "Something went wrong"
        }
    }

    init(message msg: String = "Something went wrong", code: Int = -1) {
        self.code = code
        if ErrorType.isServerError(code) {
            message = ErrorType.serverError.message
        } else {
            message = msg
        }
    }
    init(kind: Kind) {
        self.init(message: kind.message, code: kind.code)
    }

}

public extension RequestError {
    var codeType: ErrorType {
        guard let errorType = ErrorType(rawValue: code) else {
            return ErrorType.isServerError(code) ? .serverError : .unknownError
        }
        return errorType
    }
}

public struct AppMetadata {
    public let name: String
    public let url: String
    public let iconUrl: String?
    public let base64Icon: String?
    public let apiVersion: String?

    var platform: String = "ios"

    public init(name: String,
                url: String,
                iconUrl: String? = nil,
                base64Icon: String? = nil,
                apiVersion: String? = nil
    ) {
        self.name = name
        self.url = url
        self.iconUrl = iconUrl
        self.apiVersion = apiVersion
        self.base64Icon = base64Icon
    }
}

public enum Deeplink: Equatable {
    static let mmsdk = "mmsdk"
}

public extension String {
    // Encode a string to base64
    func base64Encode() -> String? {
        data(using: .utf8)?.base64EncodedString()
    }

    // Decode a base64 string to original string
    func base64Decode() -> String? {
        guard let data = Data(base64Encoded: self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}


public struct RequestInfo: Codable, Mappable {
    public let type: String
    public let originator: OriginatorInfo
    public let originatorInfo: OriginatorInfo
}

public struct OriginatorInfo: Codable, Mappable {
    public let title: String?
    public let url: String?
    public let icon: String?
    public let dappId: String?
    public let platform: String?
    public let apiVersion: String?
}


public protocol Mappable: Codable { }

public extension Mappable {
    func toDictionary() -> [String: Any]? {
        do {
            let jsonData = try JSONEncoder().encode(self)
            guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                return nil
            }
            return jsonObject
        } catch {
            print("Error encoding JSON: \(error)")
            return nil
        }
    }

    func toJsonString() -> String? {
        do {
            let jsonData = try JSONEncoder().encode(self)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

extension String: Mappable {}
extension Dictionary: Mappable where Key == String, Value: Codable {}


public enum EthereumMethod: String, CaseIterable, Codable {
    case ethSign = "eth_sign"
    case personalSign = "personal_sign"
    case watchAsset = "wallet_watchAsset"
    case ethSignTypedData = "eth_signTypedData"
    case ethRequestAccounts = "eth_requestAccounts"
    case ethSendTransaction = "eth_sendTransaction"
    case ethSignTypedDataV3 = "eth_signTypedData_v3"
    case ethSignTypedDataV4 = "eth_signTypedData_v4"
    case addEthereumChain = "wallet_addEthereumChain"
    case metamaskBatch = "metamask_batch"
    case metamaskOpen = "metamask_open"
    case personalEcRecover = "personal_ecRecover"
    case walletRevokePermissions = "wallet_revokePermissions"
    case walletRequestPermissions  = "wallet_requestPermissions"
    case walletGetPermissions = "wallet_getPermissions"
    case metamaskConnectWith = "metamask_connectwith"
    case switchEthereumChain = "wallet_switchEthereumChain"
    case metaMaskConnectSign = "metamask_connectSign"
    case unknownMethod = "unknown"

    var isResultMethod: Bool {
        let resultMethods: [EthereumMethod] = [
            .ethSign,
            .watchAsset,
            .personalSign,
            .metamaskBatch,
            .walletRevokePermissions,
            .walletGetPermissions,
            .walletRequestPermissions,
            .metaMaskConnectSign,
            .metamaskConnectWith,
            .ethSignTypedData,
            .ethRequestAccounts,
            .ethSendTransaction,
            .ethSignTypedDataV3,
            .ethSignTypedDataV4,
            .addEthereumChain,
            .switchEthereumChain,
        ]

        return resultMethods.contains(self)
    }

    var isConnectMethod: Bool {
        let connectMethods: [EthereumMethod] = [
            .metaMaskConnectSign,
            .metamaskConnectWith
        ]
        return connectMethods.contains(self)
    }
}

public enum ErrorType: Int {
    // MARK: Ethereum Provider

    case userRejectedRequest = 4001 // Ethereum Provider User Rejected Request
    case unauthorisedRequest = 4100 // Ethereum Provider User Rejected Request
    case unsupportedMethod = 4200 // Ethereum Provider Unsupported Method
    case disconnected = 4900 // Ethereum Provider Not Connected
    case chainDisconnected = 4901 // Ethereum Provider Chain Not Connected
    case unrecognizedChainId = 4902 // Unrecognized chain ID. Try adding the chain using wallet_addEthereumChain first

    // MARK: Ethereum RPC

    case invalidInput = -32000 // JSON RPC 2.0 Server error
    case transactionRejected = -32003 // Ethereum JSON RPC Transaction Rejected
    case invalidRequest = -32600 // JSON RPC 2.0 Invalid Request
    case invalidMethodParameters = -32602 // JSON RPC 2.0 Invalid Parameters
    case serverError = -32603 // Could be one of many outcomes
    case parseError = -32700 // JSON RPC 2.0 Parse error
    case unknownError = -1 // check RequestError.code instead

    static func isServerError(_ code: Int) -> Bool {
        code < -32000 && code >= -32099
    }

    var message: String {
        switch self {
        case .userRejectedRequest:
            return "User rejected the request"
        case .unauthorisedRequest:
            return "User rejected the request"
        case .unsupportedMethod:
            return "Unsupported method"
        case .disconnected:
            return "Not connected"
        case .chainDisconnected:
            return "Chain not connected"
        case .unrecognizedChainId:
            return "Unrecognized chain ID. Try adding the chain using addEthereumChain first"
        case .invalidInput:
            return "JSON RPC server error"
        case .transactionRejected:
            return "Transaction rejected"
        case .invalidRequest:
            return "Invalid request"
        case .invalidMethodParameters:
            return "Invalid method parameters"
        case .serverError:
            return "Server error"
        case .parseError:
            return "Parse error"
        case .unknownError:
            return "The request failed"
        }
    }
}
