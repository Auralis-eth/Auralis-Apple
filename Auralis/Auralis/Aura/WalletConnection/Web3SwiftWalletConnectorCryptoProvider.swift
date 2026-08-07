import Foundation
import WalletConnectorKit
import secp256k1
import web3

/// Bridges web3.swift (secp256k1) into `WalletConnectorKit`'s crypto seam so the
/// custom IRN connector can actually **verify EVM wallet ownership**.
///
/// Without a recovery-capable provider injected, `WalletConnectDAppConnector`
/// reports `.experimental` readiness and every `verifyOwnership` call fails closed
/// (`DefaultWalletConnectorCryptoProvider.recoverPublicKey` throws). This provider
/// supplies real secp256k1 public-key recovery + keccak-256 so EOA ownership
/// proofs succeed and the connector can advertise production-ready EVM identity.
///
/// - Note: `KeyUtil.recoverPublicKey(message:signature:)` returns only the derived
///   *address*, but the package's `WalletOwnershipVerifier` needs the recovered
///   *public key* (it hashes it itself). So recovery is done directly against
///   `secp256k1` here (mirroring web3.swift's own `KeyUtil` recovery) and returns
///   the 64-byte `X ‖ Y` key.
///
/// ## Smart-contract wallets (EIP-1271)
/// `supportsSmartContractOwnership` is `true` whenever at least one per-chain RPC
/// endpoint is configured (the default map covers the major EVM chains). Safe /
/// Coinbase Smart Wallet / most ERC-4337 accounts have no recoverable EOA key, so
/// EOA recovery never matches their address; `WalletOwnershipVerifier` then calls
/// `isValidERC1271Signature`, which performs an on-chain `eth_call` to the account's
/// `isValidSignature(bytes32,bytes)` and accepts the `0x1626ba7e` magic return
/// value.
///
/// - The validated `_hash` is the **EIP-191 personal-sign digest** of the challenge
///   message (what a standard `personal_sign` smart wallet validates against). Wallets
///   that wrap the hash in their own domain separator, or that are counterfactual /
///   not-yet-deployed (ERC-6492), are **not** covered by this straight
///   `isValidSignature` call and will fail closed — acceptable for an ownership gate.
/// - The default RPC endpoints are public nodes (rate-limited, best-effort). Inject a
///   keyed endpoint map (Infura/Alchemy/etc.) for production reliability.
struct Web3SwiftWalletConnectorCryptoProvider: WalletConnectorCryptoProvider {
    /// Per-chain JSON-RPC endpoints used for the EIP-1271 on-chain `eth_call`.
    let rpcEndpoints: [WalletChain: URL]
    private let urlSession: URLSession

    init(
        rpcEndpoints: [WalletChain: URL] = Web3SwiftWalletConnectorCryptoProvider.defaultRPCEndpoints,
        urlSession: URLSession = .shared
    ) {
        self.rpcEndpoints = rpcEndpoints
        self.urlSession = urlSession
    }

    var supportsRecovery: Bool { true }

    /// EIP-1271 validation is available only when at least one RPC endpoint is
    /// configured; otherwise the connector keeps its EOA-only, fail-closed behavior.
    var supportsSmartContractOwnership: Bool { !rpcEndpoints.isEmpty }

    func keccak256(_ data: Data) -> Data {
        data.web3.keccak256
    }

    /// Recovers the uncompressed secp256k1 public key (64 bytes, `X ‖ Y`) that
    /// produced `signature` over the 32-byte digest `message`. Mirrors
    /// web3.swift `KeyUtil.recoverPublicKey` but returns the key rather than the
    /// address, which is what `WalletOwnershipVerifier` expects.
    func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data {
        guard message.count == 32, signature.r.count == 32, signature.s.count == 32 else {
            throw WalletConnectionError.cryptographyFailure
        }
        guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)) else {
            throw WalletConnectionError.cryptographyFailure
        }
        defer { secp256k1_context_destroy(ctx) }

        // The package normalizes `v` to 27/28 or 0/1 for the signature's parity;
        // secp256k1 wants the 0/1 recovery id.
        let recid: Int32 = signature.v >= 27 ? Int32(signature.v) - 27 : Int32(signature.v)
        guard recid == 0 || recid == 1 else {
            throw WalletConnectionError.cryptographyFailure
        }

        var compact = signature.r + signature.s // 64 bytes: r ‖ s
        let recoverableSignature = UnsafeMutablePointer<secp256k1_ecdsa_recoverable_signature>.allocate(capacity: 1)
        defer { recoverableSignature.deallocate() }
        guard secp256k1_ecdsa_recoverable_signature_parse_compact(ctx, recoverableSignature, &compact, recid) == 1 else {
            throw WalletConnectionError.cryptographyFailure
        }

        let publicKey = UnsafeMutablePointer<secp256k1_pubkey>.allocate(capacity: 1)
        defer { publicKey.deallocate() }
        var digest = [UInt8](message)
        guard secp256k1_ecdsa_recover(ctx, publicKey, recoverableSignature, &digest) == 1 else {
            throw WalletConnectionError.cryptographyFailure
        }

        var length = 65
        var serialized = [UInt8](repeating: 0, count: length)
        secp256k1_ec_pubkey_serialize(ctx, &serialized, &length, publicKey, UInt32(SECP256K1_EC_UNCOMPRESSED))
        guard length == 65, serialized.first == 0x04 else {
            throw WalletConnectionError.cryptographyFailure
        }
        // Drop the 0x04 SEC1 prefix → 64-byte X ‖ Y, which the verifier hashes.
        return Data(serialized[1..<65])
    }

    /// Validates an EIP-1271 signature for the smart-contract account `address` on
    /// `chain` via an on-chain `eth_call` to `isValidSignature(bytes32,bytes)`.
    ///
    /// `_hash` is the EIP-191 personal-sign digest of `message` (the same digest a
    /// standard `personal_sign` contract wallet validates against). Returns `true`
    /// only when the call returns the `0x1626ba7e` magic value; an on-chain revert
    /// or non-magic return is treated as "not owned" (fail-closed, no throw). A
    /// missing endpoint or transport failure throws so the caller fails loud rather
    /// than silently reporting a smart wallet as unowned.
    func isValidERC1271Signature(address: String, message: Data, signature: Data, chain: WalletChain) async throws -> Bool {
        guard let endpoint = rpcEndpoints[chain] else {
            throw WalletConnectionError.unavailable(
                "No RPC endpoint is configured for \(chain.displayName) to validate an EIP-1271 smart-contract signature. Inject a Web3SwiftWalletConnectorCryptoProvider(rpcEndpoints:) that includes this chain."
            )
        }

        // The EIP-1271 magic value is identically the 4-byte selector of
        // `isValidSignature(bytes32,bytes)`: `bytes4(keccak256(...)) == 0x1626ba7e`.
        let magicValue = Data([0x16, 0x26, 0xba, 0x7e])
        let digest = WalletOwnershipVerifier.personalSignDigest(message: message)
        let calldata = Self.encodeIsValidSignatureCall(selector: magicValue, hash: digest, signature: signature)

        switch try await ethCall(to: address, data: calldata, endpoint: endpoint) {
        case .reverted:
            // Contract rejected the signature (or is not a 1271 validator here).
            return false
        case .result(let returned):
            // Return is a left-aligned bytes4 in a 32-byte word: `0x1626ba7e00…00`.
            return returned.prefix(4) == magicValue
        }
    }

    // MARK: - EIP-1271 helpers

    /// Public RPC endpoints for the major EVM chains. Best-effort/rate-limited;
    /// override for production. Base and Ethereum matter most for Coinbase Smart
    /// Wallet.
    static let defaultRPCEndpoints: [WalletChain: URL] = {
        let endpointsByChain: [WalletChain: String] = [
            .ethereum: "https://ethereum-rpc.publicnode.com",
            .base: "https://base-rpc.publicnode.com",
            .polygon: "https://polygon-bor-rpc.publicnode.com",
            .optimism: "https://optimism-rpc.publicnode.com",
            .arbitrum: "https://arbitrum-one-rpc.publicnode.com",
            .avalanche: "https://avalanche-c-chain-rpc.publicnode.com",
            .bnb: "https://bsc-rpc.publicnode.com",
        ]
        return endpointsByChain.reduce(into: [:]) { result, entry in
            if let url = URL(string: entry.value) { result[entry.key] = url }
        }
    }()

    private enum EthCallOutcome {
        case result(Data)
        case reverted
    }

    /// ABI-encodes `isValidSignature(bytes32 hash, bytes signature)`.
    private static func encodeIsValidSignatureCall(selector: Data, hash: Data, signature: Data) -> Data {
        var data = Data()
        data.append(selector)                       // 4-byte selector
        data.append(hash)                           // arg0: bytes32 (already 32)
        data.append(leftPadded32(UInt64(64)))       // arg1 head: offset to the bytes tail (0x40)
        data.append(leftPadded32(UInt64(signature.count))) // tail: dynamic length
        var padded = signature                      // tail: right-padded to a 32-byte boundary
        let remainder = padded.count % 32
        if remainder != 0 {
            padded.append(Data(repeating: 0, count: 32 - remainder))
        }
        data.append(padded)
        return data
    }

    /// A big-endian `UInt64` left-padded into a 32-byte ABI word.
    private static func leftPadded32(_ value: UInt64) -> Data {
        var word = Data(repeating: 0, count: 32)
        let bigEndian = withUnsafeBytes(of: value.bigEndian) { Data($0) } // 8 bytes
        word.replaceSubrange((32 - bigEndian.count)..<32, with: bigEndian)
        return word
    }

    private func ethCall(to address: String, data: Data, endpoint: URL) async throws -> EthCallOutcome {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "eth_call",
            "params": [
                ["to": address, "data": "0x" + Self.hexString(data)],
                "latest",
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WalletConnectionError.unavailable("EIP-1271 eth_call returned a non-success HTTP status.")
        }
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw WalletConnectionError.invalidResponse
        }
        // A JSON-RPC error here is almost always an execution revert (the contract
        // rejected the signature or does not expose the method) — treat as unowned.
        if json["error"] != nil {
            return .reverted
        }
        guard let resultHex = json["result"] as? String, let bytes = Self.data(hexEncoded: resultHex) else {
            throw WalletConnectionError.invalidResponse
        }
        return .result(bytes)
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func data(hexEncoded string: String) -> Data? {
        var hex = string
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex.removeFirst(2) }
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }
}
