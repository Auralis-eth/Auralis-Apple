import AuralisPrimaryModels
import BigInt
import Foundation
import ProviderKit
import web3

/// Tracks which addresses belong to Auralis's in-app self-custodial wallet, so the signer router can send
/// their signing requests to the local keystore instead of an external connector. Backed by
/// `UserDefaults` (addresses are public, not secret) for O(1) routing without a database hit.
enum InAppWalletRegistry {
    private static let key = "auralis.inapp.wallet.addresses"

    /// Appends `address` if it is not already registered, preserving registration order.
    ///
    /// Order is load-bearing despite there being only one address today. This used to round-trip
    /// through a `Set`, so `all()` came back in an arbitrary order that could differ across
    /// launches — and `InAppWalletService.primaryAddress()` is `all().first`. Derivation is fixed at
    /// account 0 / index 0 so exactly one address exists in practice, which made the hazard
    /// invisible; but `register` is additive and the API is plural, so the first time a second
    /// address is added the "primary" wallet would start changing between launches. Insertion-order
    /// dedupe costs nothing at this size and makes first-registered mean first.
    static func register(address: String) {
        let normalized = address.lowercased()
        var addresses = all()
        guard !addresses.contains(normalized) else { return }
        addresses.append(normalized)
        UserDefaults.standard.set(addresses, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func owns(address: String) -> Bool {
        all().contains(address.lowercased())
    }

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}

/// Non-isolated signing primitives, kept off the main actor so they can run inside the keystore's detached
/// `withSeed` closure (where the decrypted seed lives transiently).
enum InAppWalletCrypto {
    enum CryptoError: LocalizedError {
        case addressMismatch
        case signatureFailed

        var errorDescription: String? {
            switch self {
            case .addressMismatch: return "This wallet does not control that address."
            case .signatureFailed: return "Failed to produce a signature."
            }
        }
    }

    /// The lowercased `0x…` address controlled by `privateKey`.
    static func address(for privateKey: Data) throws -> String {
        let publicKey = try KeyUtil.generatePublicKey(from: privateKey)
        return KeyUtil.generateAddress(from: publicKey).asString()
    }

    /// EIP-191 `personal_sign` over `message`, returning the `0x…` 65-byte signature. Mirrors web3.swift's
    /// `EthereumAccount.signMessage` but signs with a transient key rather than an on-disk keystore.
    static func personalSign(message: Data, privateKey: Data) throws -> String {
        let prefix = "\u{19}Ethereum Signed Message:\n\(message.count)"
        guard var data = prefix.data(using: .ascii) else { throw CryptoError.signatureFailed }
        data.append(message)
        let hash = data.web3.keccak256

        // hashing:false — `hash` is already the 32-byte digest to sign.
        guard var signed = try? KeyUtil.sign(message: hash, with: privateKey, hashing: false),
              var recoveryByte = signed.popLast() else {
            throw CryptoError.signatureFailed
        }
        // Normalize v to the 27/28 convention wallets expect.
        if recoveryByte < 27 { recoveryByte += 27 }
        signed.append(recoveryByte)
        return signed.web3.hexString
    }
}

/// Signs for Auralis's in-app self-custodial wallet by deriving the acting key from the biometric-gated
/// keystore seed and signing locally — never routing through any connector or third-party SDK.
///
/// Both message signing and transaction signing happen *inside* the keystore's `withSeed` closure, so the
/// derived private key never escapes it; only the resulting signature / raw signed transaction (both
/// public artefacts) leave the closure. Transactions are legacy (type-0, EIP-155): nonce, gas price, and
/// gas limit are fetched from the chain's RPC first, the transaction is signed locally, then the public
/// raw signed transaction is broadcast via `eth_sendRawTransaction`.
@MainActor
final class InAppWalletSigner: WalletActionSigning {
    enum SigningError: LocalizedError {
        case unsupportedChain(String)
        case rpcUnavailable(String)
        case missingRecipient
        case malformedValue(String)
        case malformedData(String)
        case malformedAddress(String)
        case broadcastRejected(String)
        case invalidBroadcastResponse

        var errorDescription: String? {
            switch self {
            case let .unsupportedChain(id):
                return "Chain “\(id)” isn't a supported EVM network."
            case let .rpcUnavailable(name):
                return "No RPC endpoint is configured for \(name). Add an Alchemy API key to send from the in-app wallet."
            case .missingRecipient:
                return "This transaction has no recipient address."
            case let .malformedValue(value):
                return "“\(value)” is not a valid transaction value."
            case let .malformedData(data):
                return "“\(data)” is not valid transaction calldata."
            case let .malformedAddress(address):
                return "“\(address)” is not a valid Ethereum address."
            case let .broadcastRejected(message):
                return "The network rejected the transaction: \(message)"
            case .invalidBroadcastResponse:
                return "The RPC endpoint returned an unexpected response."
            }
        }
    }

    private let configurationResolver: any ProviderConfigurationResolving
    private let urlSession: URLSession

    init(
        configurationResolver: any ProviderConfigurationResolving = LiveProviderConfigurationResolver(),
        urlSession: URLSession = .shared
    ) {
        self.configurationResolver = configurationResolver
        self.urlSession = urlSession
    }

    func signPersonalMessage(_ text: String, address: String, chainID: String?) async throws -> String {
        try await InAppWalletKeystore.withSeed(
            localizedReason: "Authenticate to sign with your Auralis wallet"
        ) { seed in
            // Wiped on every exit path for the same reason the seed is: the derived key is equivalent to
            // the seed for this address, so leaving it in freed heap memory undoes the seed's zeroization.
            var privateKey = try InAppWalletDerivation.ethereumPrivateKey(seed: seed)
            defer { privateKey.resetBytes(in: 0..<privateKey.count) }
            guard try InAppWalletCrypto.address(for: privateKey).lowercased() == address.lowercased() else {
                throw InAppWalletCrypto.CryptoError.addressMismatch
            }
            return try InAppWalletCrypto.personalSign(message: Data(text.utf8), privateKey: privateKey)
        }
    }

    /// Locally signs and broadcasts a legacy (type-0, EIP-155) transaction from the in-app wallet.
    ///
    /// Nonce, gas price, and gas limit are fetched from the chain's RPC first; the transaction is then
    /// signed *inside* `withSeed` (so the derived key never escapes), and finally the public raw signed
    /// transaction is broadcast. Fails closed on an unsupported chain, a missing endpoint, malformed
    /// inputs, a gas-estimation revert, or a broadcast rejection — never a silent no-op.
    func sendTransaction(
        from address: String,
        to: String?,
        value: String,
        data: String,
        chainID: String
    ) async throws -> String {
        guard let to, !to.isEmpty else { throw SigningError.missingRecipient }
        guard let chain = Self.resolveChain(chainID) else { throw SigningError.unsupportedChain(chainID) }

        let configuration = try configurationResolver.configuration(for: chain)
        guard let rpcURL = configuration.alchemyRPCURL else {
            throw SigningError.rpcUnavailable(chain.routingDisplayName)
        }
        guard let valueQuantity = Self.parseQuantity(value) else { throw SigningError.malformedValue(value) }
        let callData = try Self.parseCallData(data)

        // Both addresses are checked for shape before the RPC round-trip. web3.swift's RLP encoder
        // falls back to UTF-8 bytes for a non-hex address string rather than failing, so a malformed
        // `to` would RLP-encode as arbitrary bytes. The node rejects it first today — gas estimation
        // runs before any key material is touched — but that makes the failure an opaque RPC error
        // rather than a named field, and relies on the estimate ordering never changing.
        guard Self.isHexAddress(address) else { throw SigningError.malformedAddress(address) }
        guard Self.isHexAddress(to) else { throw SigningError.malformedAddress(to) }

        let client = EthereumHttpClient(url: rpcURL, network: .custom("\(chain.chainId)"))
        let fromAddress = EthereumAddress(address)
        let toAddress = EthereumAddress(to)

        // Fetch the chain-derived transaction parameters before touching any key material.
        let nonce = try await client.eth_getTransactionCount(address: fromAddress, block: .Pending)
        let gasPrice = try await client.eth_gasPrice()
        let estimateTransaction = EthereumTransaction(
            from: fromAddress,
            to: toAddress,
            value: valueQuantity,
            data: callData,
            nonce: nonce,
            gasPrice: gasPrice,
            gasLimit: nil,
            chainId: chain.chainId
        )
        let estimatedGas = try await client.eth_estimateGas(estimateTransaction)
        // +25% headroom so a slightly-underestimated limit doesn't cause an out-of-gas revert on chain.
        let gasLimit = estimatedGas + estimatedGas / 4

        // Only Sendable primitives cross into the @Sendable signing closure; the non-Sendable transaction
        // and account are rebuilt and consumed inside it, so only the public raw hex escapes.
        let chainId = chain.chainId
        let valueHex = Self.hexQuantity(valueQuantity)
        let gasPriceHex = Self.hexQuantity(gasPrice)
        let gasLimitHex = Self.hexQuantity(gasLimit)
        let dataHex = callData.web3.hexString

        let rawSignedHex = try await InAppWalletKeystore.withSeed(
            localizedReason: "Authenticate to send a transaction from your Auralis wallet"
        ) { seed in
            // Wiped on every exit path — see `signPersonalMessage`.
            var privateKey = try InAppWalletDerivation.ethereumPrivateKey(seed: seed)
            defer { privateKey.resetBytes(in: 0..<privateKey.count) }
            guard try InAppWalletCrypto.address(for: privateKey).lowercased() == address.lowercased() else {
                throw InAppWalletCrypto.CryptoError.addressMismatch
            }
            // Each quantity reports itself. Collapsing these into one guard named the *value* even
            // when the gas price or limit was the unparsable one, which points a diagnosis at the
            // one field the user chose and away from the two the chain supplied.
            guard let value = BigUInt(valueHex.dropFirst(2), radix: 16) else {
                throw SigningError.malformedValue(valueHex)
            }
            guard let gasPrice = BigUInt(gasPriceHex.dropFirst(2), radix: 16) else {
                throw SigningError.malformedValue(gasPriceHex)
            }
            guard let gasLimit = BigUInt(gasLimitHex.dropFirst(2), radix: 16) else {
                throw SigningError.malformedValue(gasLimitHex)
            }
            // Fails closed like the three quantities above. A `?? Data()` here would sign and broadcast
            // an ERC-20 approve as a 0-value, 0-calldata no-op against the token contract — gas already
            // estimated for the real calldata, and a receipt claiming the approval landed.
            guard let callPayload = Data(hex: dataHex) else {
                throw SigningError.malformedData(dataHex)
            }
            let transaction = EthereumTransaction(
                from: EthereumAddress(address),
                to: EthereumAddress(to),
                value: value,
                data: callPayload,
                nonce: nonce,
                gasPrice: gasPrice,
                gasLimit: gasLimit,
                chainId: chainId
            )
            let account = try EthereumAccount(keyStorage: TransientSingleKeyStorage(privateKey: privateKey))
            return try account.signRaw(transaction).web3.hexString
        }

        return try await broadcastRawTransaction(rawSignedHex, rpcURL: rpcURL)
    }

    // MARK: - Broadcast

    /// Broadcasts an already-signed raw transaction via `eth_sendRawTransaction`, returning the tx hash.
    private func broadcastRawTransaction(_ rawHex: String, rpcURL: URL) async throws -> String {
        // A fresh id per call, checked against the response below, so a multiplexed or proxied reply
        // cannot be matched to the wrong request. Negligible against a single-shot POST, but the
        // transaction hash this returns is what the receipt records as having been broadcast.
        let requestID = Int.random(in: 1...Int(Int32.max))
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "eth_sendRawTransaction",
            "params": [rawHex]
        ]
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SigningError.broadcastRejected("HTTP \(status)")
        }
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw SigningError.invalidBroadcastResponse
        }
        // Refuse a reply that does not answer *this* request rather than reading someone else's result.
        guard (json["id"] as? Int) == requestID else {
            throw SigningError.invalidBroadcastResponse
        }
        if let error = json["error"] as? [String: Any] {
            throw SigningError.broadcastRejected((error["message"] as? String) ?? "unknown error")
        }
        guard let hash = json["result"] as? String else { throw SigningError.invalidBroadcastResponse }
        return hash
    }

    // MARK: - Parsing helpers

    /// Maps a payload chain id (`0x1`, `1`, or `eip155:1`) to a supported ``Chain``.
    static func resolveChain(_ chainID: String) -> Chain? {
        guard let id = numericChainID(chainID) else { return nil }
        return Chain.allCases.first { $0.chainId == id }
    }

    static func numericChainID(_ raw: String) -> Int? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("eip155:") { value = String(value.dropFirst("eip155:".count)) }
        if value.hasPrefix("0x") { return Int(value.dropFirst(2), radix: 16) }
        return Int(value)
    }

    /// Parses a decimal or `0x`-hex quantity (value in wei) into a `BigUInt`; empty is treated as zero.
    static func parseQuantity(_ raw: String) -> BigUInt? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return BigUInt(0) }
        if trimmed.lowercased().hasPrefix("0x") { return BigUInt(trimmed.dropFirst(2), radix: 16) }
        return BigUInt(trimmed, radix: 10)
    }

    /// Parses `0x`-hex calldata; empty / `0x` means no calldata (a plain value transfer).
    static func parseCallData(_ raw: String) throws -> Data {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "0x" { return Data() }
        guard let data = Data(hex: trimmed) else { throw SigningError.malformedData(raw) }
        return data
    }

    /// A `0x`-prefixed hex string for a `BigUInt` quantity.
    static func hexQuantity(_ value: BigUInt) -> String {
        "0x" + String(value, radix: 16)
    }

    /// Whether `value` is a `0x`-prefixed 20-byte address in ASCII hex.
    ///
    /// ASCII-only for the reason given on `ERC20ApproveCallData`: `Character.isHexDigit` is
    /// Unicode-aware and accepts fullwidth forms that no address encoder can parse.
    static func isHexAddress(_ value: String) -> Bool {
        guard value.count == 42, value.lowercased().hasPrefix("0x") else { return false }
        return value.dropFirst(2).allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}

/// A single-key `EthereumSingleKeyStorageProtocol` holding a transient derived key for exactly one signing
/// operation. Created and discarded inside the keystore's `withSeed` closure so the key never persists.
private final class TransientSingleKeyStorage: EthereumSingleKeyStorageProtocol {
    private var privateKey: Data

    init(privateKey: Data) { self.privateKey = privateKey }

    /// Wipes this object's copy of the key.
    ///
    /// The signer's own `defer { privateKey.resetBytes(...) }` only zeroes the buffer it uniquely owns;
    /// `Data` is copy-on-write, so this second reference keeps the key material alive until the storage
    /// object is released. Clearing it here closes that window rather than leaving the derived spending
    /// key in freed heap memory after the seed itself has been zeroized.
    deinit {
        privateKey.resetBytes(in: 0..<privateKey.count)
    }

    func storePrivateKey(key: Data) throws { }

    func loadPrivateKey() throws -> Data { privateKey }
}
