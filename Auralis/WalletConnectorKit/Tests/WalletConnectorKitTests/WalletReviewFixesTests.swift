import Foundation
import Testing
@testable import WalletConnectorKit

@Suite("Review fixes")
struct WalletReviewFixesTests {
    // MARK: - #3 isCanonicalV2 enforcement for externally-scanned URIs

    @Test("External scanned URI rejects a truncated symmetric key")
    func externalURIRejectsShortKey() {
        let shortKey = "wc:topic@2?relay-protocol=irn&symKey=abcd&expiryTimestamp=1800000000"
        #expect(WalletConnectURI(externalScannedString: shortKey) == nil)
        // The permissive parser still accepts it for test fixtures.
        #expect(WalletConnectURI(absoluteString: shortKey) != nil)
    }

    @Test("External scanned URI accepts a canonical 32-byte key")
    func externalURIAcceptsCanonicalKey() throws {
        let key = String(repeating: "a", count: 64)
        let uri = "wc:\(String(repeating: "b", count: 64))@2?relay-protocol=irn&symKey=\(key)&expiryTimestamp=1800000000"
        let parsed = try #require(WalletConnectURI(externalScannedString: uri))
        #expect(parsed.isCanonicalV2)
    }

    // MARK: - #4 EVM address / hex validation

    @Test("eth_sendTransaction rejects a malformed from address")
    func rejectsBadFromAddress() {
        let request = WalletRequest(
            id: "r",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethSendTransaction,
            params: [.object([
                "from": .string("0x123"), // too short
                "to": .string("0x742d35Cc6634C0532925a3b844Bc454e4438f44e"),
                "value": .string("0x0"),
                "data": .string("0x"),
                "chainId": .string("0x1"),
            ])]
        )
        #expect(throws: WalletConnectionError.self) {
            try WalletRequestValidation.validate(request)
        }
    }

    @Test("eth_sendTransaction accepts valid addresses and hex data")
    func acceptsValidTransaction() throws {
        let request = WalletRequest(
            id: "r",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethSendTransaction,
            params: [.object([
                "from": .string("0x742d35Cc6634C0532925a3b844Bc454e4438f44e"),
                "to": .string("0x742d35Cc6634C0532925a3b844Bc454e4438f44e"),
                "value": .string("0x0"),
                "data": .string("0xabcd"),
                "chainId": .string("0x1"),
            ])]
        )
        try WalletRequestValidation.validate(request)
    }

    // MARK: - #2 ownership verifier

    private struct StubCryptoProvider: WalletConnectorCryptoProvider {
        let publicKey: Data
        func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data { publicKey }
        func keccak256(_ data: Data) -> Data { EthereumKeccak256.hash(data) }
    }

    @Test("Ownership verifier recovers the expected EVM address")
    func ownershipVerifierMatchesAddress() throws {
        let pubKey = Data((0..<64).map { UInt8($0) })
        let provider = StubCryptoProvider(publicKey: pubKey)
        let expected = "0x" + EthereumKeccak256.hash(pubKey).suffix(20).map { String(format: "%02x", $0) }.joined()
        let signature = WalletEthereumSignature(v: 27, r: [], s: [])

        #expect(try WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: expected.uppercased(),
            message: Data("hello".utf8),
            signature: signature,
            using: provider
        ))
        #expect(try !WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: "0x0000000000000000000000000000000000000000",
            message: Data("hello".utf8),
            signature: signature,
            using: provider
        ))
    }
}
