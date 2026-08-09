import Foundation
import Security
import Testing
@testable import WalletConnectorKit
@testable import WalletConnectorKitCoinbaseAdapter
@testable import WalletConnectorKitReownAdapter

#if os(iOS)
@preconcurrency import ReownAppKit
#endif

@Suite("Wallet account parsing")
struct WalletAccountParsingTests {
    @Test(
        "Parses supported CAIP-10 accounts",
        arguments: [
            ("eip155:1:0x0000000000000000000000000000000000000000", "eip155:1", "0x0000000000000000000000000000000000000000", WalletChain.ethereum),
            ("eip155:137:0x1111111111111111111111111111111111111111", "eip155:137", "0x1111111111111111111111111111111111111111", WalletChain.polygon),
            ("eip155:8453:0x2222222222222222222222222222222222222222", "eip155:8453", "0x2222222222222222222222222222222222222222", WalletChain.base),
            ("solana:mainnet:11111111111111111111111111111111", "solana:mainnet", "11111111111111111111111111111111", WalletChain.solana),
            ("solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp:11111111111111111111111111111111", "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", "11111111111111111111111111111111", WalletChain.solana),
        ]
    )
    func parsesSupportedAccounts(caip10: String, caip2: String, address: String, chain: WalletChain) throws {
        let account = try #require(WalletAccountParser.parse(caip10))
        #expect(account.blockchain.caip2 == caip2)
        #expect(account.address == address)
        #expect(account.blockchain.knownChain == chain)
        #expect(account.caip10 == caip10)
    }

    @Test(
        "Rejects unsupported or malformed CAIP-10 accounts",
        arguments: [
            "",
            ":1:0x0000000000000000000000000000000000000000",
            "eip155::0x0000000000000000000000000000000000000000",
            "eip155:1:",
            "eip155:1",
            "eip155:1:not-an-address",
            "eip155:1:0x000000000000000000000000000000000000000",
            "eip155:1:0x000000000000000000000000000000000000000g",
            "eip155:999:0x0000000000000000000000000000000000000000",
            "solana:mainnet:0x0000000000000000000000000000000000000000",
            "solana:mainnet:0OIl1111111111111111111111111111",
            "cosmos:cosmoshub-4:cosmos1address",
        ]
    )
    func rejectsMalformedAccounts(caip10: String) {
        #expect(WalletAccountParser.parse(caip10) == nil)
    }
}

@Suite("Wallet namespaces and requests")
struct WalletNamespaceAndRequestTests {
    @Test("Default namespace proposal matches V1 EVM and Solana scope")
    func defaultNamespaceProposalMatchesV1Scope() {
        let proposal = WalletNamespaceProposalSet.defaultV1

        #expect(proposal.proposals["eip155"]?.chains.map(\.caip2) == ["eip155:1", "eip155:137", "eip155:8453", "eip155:10", "eip155:42161", "eip155:43114", "eip155:56", "eip155:324", "eip155:59144"])
        #expect(proposal.proposals["eip155"]?.methods == WalletConnectionNamespaces.evmMethods)
        #expect(proposal.proposals["eip155"]?.events == WalletConnectionNamespaces.evmEvents)
        #expect(proposal.proposals["solana"]?.chains.map(\.caip2) == ["solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"])
        #expect(proposal.proposals["solana"]?.methods == WalletConnectionNamespaces.solanaMethods)
        #expect(proposal.proposals["solana"]?.events == [])
    }

    @Test("Default session proposal can keep broad capabilities optional")
    func defaultSessionProposalCanKeepBroadCapabilitiesOptional() {
        let request = WalletSessionProposalRequest.defaultV1Optional

        #expect(request.requiredNamespaces.isEmpty)
        #expect(request.optionalNamespaces.proposals.keys.sorted() == ["eip155", "solana"])
        #expect(request.mergedProposalSet == .defaultV1)
    }

    @Test("Request builders create deterministic request payloads")
    func requestBuildersCreateDeterministicPayloads() throws {
        let evm = WalletRequestBuilder.personalSign(
            id: "request-1",
            address: "0x0000000000000000000000000000000000000000",
            message: "Hello",
            chain: .base,
            expiryDate: .sampleDate
        )
        let solana = WalletRequestBuilder.solanaSignMessage(
            id: "request-2",
            address: "11111111111111111111111111111111",
            message: "Hello",
            expiryDate: .sampleDate
        )
        let typedData = WalletRequestBuilder.signTypedDataV4(
            id: "request-3",
            address: "0x0000000000000000000000000000000000000000",
            typedDataJSON: "{\"domain\":{}}",
            chain: .ethereum,
            expiryDate: .sampleDate
        )
        let transaction = WalletRequestBuilder.sendTransaction(
            id: "request-4",
            transaction: WalletTransactionRequest(
                from: "0x0000000000000000000000000000000000000000",
                value: "0x0",
                data: "0x",
                chainId: "0x1"
            ),
            expiryDate: .sampleDate
        )
        let switchChain = WalletRequestBuilder.switchEthereumChain(
            id: "request-5",
            chainId: "0x2105",
            expiryDate: .sampleDate
        )
        let watchAsset = WalletRequestBuilder.watchAsset(
            id: "request-6",
            request: WalletWatchAssetRequest(address: "0x3333333333333333333333333333333333333333", symbol: "TOK", decimals: 18),
            expiryDate: .sampleDate
        )
        let solanaTransaction = WalletRequestBuilder.solanaSignTransaction(
            id: "request-7",
            serializedTransaction: "serialized-transaction",
            encoding: .base64,
            expiryDate: .sampleDate
        )
        let solanaSignAndSend = WalletRequestBuilder.solanaSignAndSendTransaction(
            id: "request-8",
            serializedTransaction: "serialized-transaction",
            encoding: .base64,
            expiryDate: .sampleDate
        )
        let solanaTransactions = try WalletRequestBuilder.solanaSignAllTransactions(
            id: "request-9",
            serializedTransactions: ["serialized-transaction-1", "serialized-transaction-2"],
            encoding: .base64,
            expiryDate: .sampleDate
        )

        #expect(evm.chain.caip2 == "eip155:8453")
        #expect(evm.method == .ethPersonalSign)
        #expect(evm.params == [.string("Hello"), .string("0x0000000000000000000000000000000000000000")])
        #expect(solana.chain.caip2 == "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp")
        #expect(solana.method == .solanaSignMessage)
        #expect(solana.params == [.string("Hello"), .string("11111111111111111111111111111111")])
        #expect(typedData.method == .ethSignTypedDataV4)
        #expect(typedData.params == [.string("0x0000000000000000000000000000000000000000"), .string("{\"domain\":{}}")])
        #expect(transaction.method == .ethSendTransaction)
        #expect(transaction.params.first?.objectValue?["chainId"] == .string("0x1"))
        #expect(switchChain.method == .walletSwitchEthereumChain)
        #expect(switchChain.params == [.object(["chainId": .string("0x2105")])])
        #expect(watchAsset.method == .walletWatchAsset)
        #expect(watchAsset.params.first?.objectValue?["options"]?.objectValue?["symbol"] == .string("TOK"))
        #expect(solanaTransaction.method == .solanaSignTransaction)
        #expect(solanaTransaction.params.first?.objectValue?["encoding"] == .string("base64"))
        #expect(solanaTransaction.params.first?.objectValue?["transaction"] == .string("serialized-transaction"))
        #expect(solanaSignAndSend.method == .solanaSignAndSendTransaction)
        #expect(solanaSignAndSend.params.first?.objectValue?["encoding"] == .string("base64"))
        #expect(solanaTransactions.method == .solanaSignAllTransactions)
        #expect(solanaTransactions.params.first?.objectValue?["encoding"] == .string("base64"))
        #expect(solanaTransactions.params.first?.objectValue?["transactions"]?.arrayValue?.contains(.string("serialized-transaction-2")) == true)
        try assertRoundTrip(evm)
        try assertRoundTrip(solana)
        try assertRoundTrip(typedData)
        try assertRoundTrip(transaction)
        try assertRoundTrip(switchChain)
        try assertRoundTrip(watchAsset)
        try assertRoundTrip(solanaTransaction)
        try assertRoundTrip(solanaSignAndSend)
        try assertRoundTrip(solanaTransactions)
        try WalletRequestValidation.validate(transaction)
        try WalletRequestValidation.validate(switchChain)
        try WalletRequestValidation.validate(watchAsset)
        try WalletRequestValidation.validate(solanaTransaction)
        try WalletRequestValidation.validate(solanaSignAndSend)
        try WalletRequestValidation.validate(solanaTransactions)
    }

    @Test("Session grant validation rejects unapproved chain method and signer")
    func sessionGrantValidationRejectsUnapprovedRequests() throws {
        let session = WalletConnectorSession(
            id: "topic-1",
            topic: "topic-1",
            providerID: "mock",
            providerName: "Mock",
            accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000001")],
            namespaces: [
                WalletSessionNamespace(
                    name: "eip155",
                    accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000001")],
                    methods: [WalletRequestMethod.ethPersonalSign.rawValue],
                    events: ["chainChanged"]
                ),
            ],
            expiryDate: .sampleDate
        )
        let ungrantedChain = WalletRequestBuilder.personalSignText(
            id: "bad-chain",
            address: "0x0000000000000000000000000000000000000001",
            text: "hello",
            chain: .polygon,
            expiryDate: .sampleDate
        )
        let ungrantedMethod = WalletRequestBuilder.sendTransaction(
            id: "bad-method",
            transaction: WalletTransactionRequest(
                from: "0x0000000000000000000000000000000000000001",
                value: "0x0",
                data: "0x",
                chainId: "0x1"
            ),
            expiryDate: .sampleDate
        )
        let ungrantedSigner = WalletRequestBuilder.personalSignText(
            id: "bad-signer",
            address: "0x0000000000000000000000000000000000000002",
            text: "hello",
            expiryDate: .sampleDate
        )

        try WalletSessionGrantValidator.validate(
            WalletRequestBuilder.personalSignText(
                id: "ok",
                address: "0x0000000000000000000000000000000000000001",
                text: "hello",
                expiryDate: .sampleDate
            ),
            in: session
        )
        #expect(throws: WalletConnectionError.unsupportedChain(.polygon)) {
            try WalletSessionGrantValidator.validate(ungrantedChain, in: session)
        }
        #expect(throws: WalletConnectionError.unsupportedMethod(WalletRequestMethod.ethSendTransaction.rawValue)) {
            try WalletSessionGrantValidator.validate(ungrantedMethod, in: session)
        }
        #expect(throws: WalletConnectionError.invalidAccount("0x0000000000000000000000000000000000000002")) {
            try WalletSessionGrantValidator.validate(ungrantedSigner, in: session)
        }
    }

    @Test("Request validation rejects namespace and parameter mismatches")
    func requestValidationRejectsNamespaceAndParameterMismatches() throws {
        let evmMethodOnSolana = WalletRequest(
            id: "bad-namespace",
            chain: WalletBlockchain(namespace: "solana", reference: "mainnet"),
            method: .ethPersonalSign,
            params: ["Hello", "11111111111111111111111111111111"],
            expiryDate: .sampleDate
        )
        let missingParam = WalletRequest(
            id: "bad-params",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethPersonalSign,
            params: ["Hello"],
            expiryDate: .sampleDate
        )

        #expect(throws: WalletConnectionError.unsupportedChain(.solana)) {
            try WalletRequestValidation.validate(evmMethodOnSolana)
        }
        #expect(throws: WalletConnectionError.invalidResponse) {
            try WalletRequestValidation.validate(missingParam)
        }
    }

    @Test("Request validation enforces WalletConnect expiry bounds")
    func requestValidationEnforcesWalletConnectExpiryBounds() throws {
        let tooShort = WalletRequestBuilder.personalSignText(
            id: "too-short",
            address: "0x0000000000000000000000000000000000000001",
            text: "hello",
            expiryDate: Date().addingTimeInterval(60)
        )
        let tooLong = WalletRequestBuilder.personalSignText(
            id: "too-long",
            address: "0x0000000000000000000000000000000000000001",
            text: "hello",
            expiryDate: Date().addingTimeInterval(604_801)
        )
        let valid = WalletRequestBuilder.personalSignText(
            id: "valid-expiry",
            address: "0x0000000000000000000000000000000000000001",
            text: "hello",
            expiryDate: Date().addingTimeInterval(3_600)
        )

        #expect(throws: WalletConnectionError.requestTimedOut("too-short")) {
            try WalletRequestValidation.validate(tooShort)
        }
        #expect(throws: WalletConnectionError.requestTimedOut("too-long")) {
            try WalletRequestValidation.validate(tooLong)
        }
        try WalletRequestValidation.validate(valid)
    }

    @Test("Request validation rejects malformed watch-asset addresses")
    func requestValidationRejectsMalformedWatchAssetAddresses() throws {
        let malformed = WalletRequest(
            id: "bad-watch-asset",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .walletWatchAsset,
            params: [.object([
                "type": .string("ERC20"),
                "options": .object([
                    "address": .string("0x1234"),
                    "symbol": .string("BAD"),
                    "decimals": .int(18),
                ]),
            ])],
            expiryDate: .sampleDate
        )

        #expect(throws: WalletConnectionError.invalidAccount("0x1234")) {
            try WalletRequestValidation.validate(malformed)
        }
    }

    @Test("Request validation rejects malformed EVM quantity strings")
    func requestValidationRejectsMalformedEVMQuantityStrings() throws {
        let decimalChainID = WalletRequestBuilder.switchEthereumChain(
            id: "decimal-chain",
            chainId: "1",
            expiryDate: .sampleDate
        )
        let leadingZeroChainID = WalletRequestBuilder.switchEthereumChain(
            id: "leading-zero-chain",
            chainId: "0x01",
            expiryDate: .sampleDate
        )
        let transaction = WalletRequestBuilder.sendTransaction(
            id: "bad-transaction",
            transaction: WalletTransactionRequest(
                from: "0x0000000000000000000000000000000000000000",
                value: "0x00",
                data: "0x",
                chainId: "0x1"
            ),
            expiryDate: .sampleDate
        )

        #expect(throws: WalletConnectionError.invalidChain("1")) {
            try WalletRequestValidation.validate(decimalChainID)
        }
        #expect(throws: WalletConnectionError.invalidChain("0x01")) {
            try WalletRequestValidation.validate(leadingZeroChainID)
        }
        #expect(throws: WalletConnectionError.invalidResponse) {
            try WalletRequestValidation.validate(transaction)
        }
    }

    @Test("Request validation accepts transactions that omit optional value and data")
    func requestValidationAcceptsSparseTransactions() throws {
        // Per EIP-1193 only `from` is required; `value`/`data` are optional.
        let sparse = WalletRequest(
            id: "sparse-transaction",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethSendTransaction,
            params: [.object([
                "from": .string("0x0000000000000000000000000000000000000001"),
                "chainId": .string("0x1"),
            ])],
            expiryDate: .sampleDate
        )

        try WalletRequestValidation.validate(sparse)
    }

    @Test("WalletConnect Solana transaction requests require base64 encoding")
    func walletConnectSolanaTransactionRequestsRequireBase64Encoding() throws {
        let transaction = WalletRequestBuilder.solanaSignTransaction(
            id: "base58-solana-transaction",
            serializedTransaction: "serialized-transaction",
            encoding: .base58,
            expiryDate: .sampleDate
        )
        let transactions = try WalletRequestBuilder.solanaSignAllTransactions(
            id: "base58-solana-transactions",
            serializedTransactions: ["serialized-transaction"],
            encoding: .base58,
            expiryDate: .sampleDate
        )

        #expect(throws: WalletConnectionError.invalidResponse) {
            try WalletRequestValidation.validate(transaction)
        }
        #expect(throws: WalletConnectionError.invalidResponse) {
            try WalletRequestValidation.validate(transactions)
        }
    }

    @Test("Semantic wallet operations produce chain-specific request payloads")
    func semanticWalletOperationsProduceChainSpecificRequests() throws {
        let evm = try WalletOperation.evm(.personalSign(address: "0x0000000000000000000000000000000000000000", message: "Hello", chain: .base))
            .walletRequest(id: "semantic-evm", expiryDate: .sampleDate)
        let solanaTransaction = WalletSolanaSerializedTransaction(
            value: "serialized-transaction",
            encoding: .base64,
            recentBlockhash: "blockhash",
            lastValidBlockHeight: 10,
            blockhashExpiresAt: .sampleDate
        )
        let solana = try WalletOperation.solana(.signTransaction(solanaTransaction))
            .walletRequest(id: "semantic-solana", expiryDate: .sampleDate)

        #expect(evm.chain.caip2 == "eip155:8453")
        #expect(evm.params == [.string("0x48656c6c6f"), .string("0x0000000000000000000000000000000000000000")])
        let raw = WalletRequestBuilder.personalSign(id: "raw-evm", address: "0x0000000000000000000000000000000000000000", message: "0xdeadbeef", expiryDate: .sampleDate)
        #expect(raw.params.first == .string("0xdeadbeef"))
        #expect(solana.chain.caip2 == "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp")
        #expect(solana.params.first?.objectValue?["encoding"] == .string("base64"))
        #expect(solanaTransaction.hasExpiredBlockhash(now: .sampleDate.addingTimeInterval(1)))
    }

    @Test("Semantic Solana batches reject mixed encodings")
    func semanticSolanaBatchesRejectMixedEncodings() {
        let operation = WalletOperation.solana(.signAllTransactions([
            WalletSolanaSerializedTransaction(value: "one", encoding: .base64),
            WalletSolanaSerializedTransaction(value: "two", encoding: .base58),
        ]))

        #expect(throws: WalletConnectionError.invalidResponse) {
            _ = try operation.walletRequest(id: "mixed-encoding", expiryDate: .sampleDate)
        }
    }
}

@Suite("WalletConnect deep links")
struct WalletConnectDeepLinkTests {
    @Test(
        "Keychain session topic store saves loads updates lists and deletes real records",
        .enabled(if: realKeychainSessionTopicStoreIsAvailable)
    )
    func keychainSessionTopicStorePersistsRealRecords() async throws {
        let service = uniqueKeychainService()
        try deleteAllKeychainTopicRecords(service: service)
        defer { try? deleteAllKeychainTopicRecords(service: service) }

        let store = KeychainWalletSessionTopicStore(service: service)
        try await store.save(topic: "topic-1", walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum)

        #expect(try await store.load(walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum) == "topic-1")
        #expect(try keychainTopicAttributes(service: service, walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum)?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(try keychainTopicAttributes(service: service, walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum)?[kSecAttrSynchronizable as String] as? Bool == false)

        try await store.save(topic: "topic-2", walletAddress: "0x0000000000000000000000000000000000000000", chain: .base)
        #expect(try await store.load(walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum) == "topic-1")
        #expect(try await store.load(walletAddress: "0x0000000000000000000000000000000000000000", chain: .base) == "topic-2")
        #expect(Set(try await store.loadAll()) == Set([
            WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-1", chain: .ethereum),
            WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-2", chain: .base),
        ]))

        try await store.delete(walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum)
        try await store.delete(walletAddress: "0x0000000000000000000000000000000000000000", chain: .base)
        try await store.delete(walletAddress: "0x0000000000000000000000000000000000000000", chain: .base)
        #expect(try await store.load(walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum) == nil)
        #expect(try await store.load(walletAddress: "0x0000000000000000000000000000000000000000", chain: .base) == nil)
        #expect(try await store.loadAll().isEmpty)
    }

    @Test(
        "Keychain session topic store migrates existing records to hardened accessibility",
        .enabled(if: realKeychainSessionTopicStoreIsAvailable)
    )
    func keychainSessionTopicStoreMigratesExistingRecordAccessibility() async throws {
        let service = uniqueKeychainService()
        try deleteAllKeychainTopicRecords(service: service)
        defer { try? deleteAllKeychainTopicRecords(service: service) }

        let factory = KeychainSessionTopicQueryFactory(service: service)
        var legacy = factory.addQuery(
            walletAddress: "0x0000000000000000000000000000000000000000",
            topicData: Data("legacy-topic".utf8),
            chain: .ethereum
        )
        legacy[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        #expect(SecItemAdd(legacy as CFDictionary, nil) == errSecSuccess)

        let store = KeychainWalletSessionTopicStore(service: service)
        try await store.save(topic: "migrated-topic", walletAddress: "0x0000000000000000000000000000000000000000", chain: .base)

        let storedAttributes = try keychainTopicAttributes(service: service, walletAddress: "0x0000000000000000000000000000000000000000", chain: .base)
        let attributes = try #require(storedAttributes)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(try await store.load(walletAddress: "0x0000000000000000000000000000000000000000") == "migrated-topic")
    }

    @Test(
        "Keychain session state store migrates existing records to hardened accessibility",
        .enabled(if: realKeychainSessionTopicStoreIsAvailable)
    )
    func keychainSessionStateStoreMigratesExistingRecordAccessibility() async throws {
        let service = uniqueKeychainService()
        try deleteKeychainSessionStateRecord(service: service)
        defer { try? deleteKeychainSessionStateRecord(service: service) }

        let legacySession = WalletConnectPersistedSession(
            sessionTopic: "legacy-session",
            pairingTopic: "legacy-pairing",
            sessionSymmetricKeyHex: String(repeating: "0", count: 64),
            selfPrivateKeyHex: nil,
            providerID: "mock",
            providerName: "Mock",
            accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000")],
            namespaces: [],
            connectedAt: .sampleDate,
            expiryDate: .sampleDate.addingTimeInterval(3600)
        )
        let legacyData = try JSONEncoder.walletConnectorTest.encode([legacySession])
        var legacy = keychainSessionStateBaseQuery(service: service)
        legacy[kSecValueData as String] = legacyData
        legacy[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        #expect(SecItemAdd(legacy as CFDictionary, nil) == errSecSuccess)

        let migratedSession = WalletConnectPersistedSession(
            sessionTopic: "migrated-session",
            pairingTopic: "migrated-pairing",
            sessionSymmetricKeyHex: String(repeating: "1", count: 64),
            selfPrivateKeyHex: nil,
            providerID: "mock",
            providerName: "Mock",
            accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000")],
            namespaces: [],
            connectedAt: .sampleDate,
            expiryDate: .sampleDate.addingTimeInterval(3600)
        )
        let store = KeychainWalletConnectSessionStateStore(service: service)
        try await store.save(migratedSession)

        let storedAttributes = try keychainSessionStateAttributes(service: service)
        let attributes = try #require(storedAttributes)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(try await store.loadAll().map(\.sessionTopic).sorted() == ["legacy-session", "migrated-session"])
    }

    @Test(
        "Keychain session topic store lists multiple real records",
        .enabled(if: realKeychainSessionTopicStoreIsAvailable)
    )
    func keychainSessionTopicStoreListsMultipleRealRecords() async throws {
        let service = uniqueKeychainService()
        try deleteAllKeychainTopicRecords(service: service)
        defer { try? deleteAllKeychainTopicRecords(service: service) }

        let store = KeychainWalletSessionTopicStore(service: service)
        try await store.save(topic: "topic-eth", walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum)
        try await store.save(topic: "topic-sol", walletAddress: "11111111111111111111111111111111", chain: .solana)
        try await store.save(topic: "topic-base", walletAddress: "0x2222222222222222222222222222222222222222", chain: .base)

        #expect(Set(try await store.loadAll()) == Set([
            WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-eth", chain: .ethereum),
            WalletSessionTopicRecord(address: "11111111111111111111111111111111", topic: "topic-sol", chain: .solana),
            WalletSessionTopicRecord(address: "0x2222222222222222222222222222222222222222", topic: "topic-base", chain: .base),
        ]))
    }

    @Test("Topic-store account keys are namespaced and never collide with other record kinds (AUD-032)")
    func topicStoreAccountKeysAreNamespaced() {
        let evm = KeychainSessionTopicQueryFactory.recordIdentifier(address: "0xABC", chain: .ethereum)
        let bare = KeychainSessionTopicQueryFactory.recordIdentifier(address: "0xABC", chain: nil)
        #expect(evm.hasPrefix(KeychainSessionTopicQueryFactory.accountPrefix))
        #expect(bare.hasPrefix(KeychainSessionTopicQueryFactory.accountPrefix))

        // Round-trips through parsing (both the namespaced and a bare legacy form).
        let parsedEVM = KeychainSessionTopicQueryFactory.parseRecordIdentifier(evm)
        #expect(parsedEVM.address == "0xABC")
        #expect(parsedEVM.chain == .ethereum)
        let parsedBare = KeychainSessionTopicQueryFactory.parseRecordIdentifier(bare)
        #expect(parsedBare.address == "0xABC")
        #expect(parsedBare.chain == nil)
        let parsedLegacy = KeychainSessionTopicQueryFactory.parseRecordIdentifier("eip155:1:0xABC")
        #expect(parsedLegacy.address == "0xABC")
        #expect(parsedLegacy.chain == .ethereum)

        // Never collides with a foreign record kind that shares the keychain service.
        for kind in [WalletKeychainRecordKind.relayAuthIdentity, .sessionRecord] {
            #expect(evm != kind.rawValue)
            #expect(!evm.hasPrefix(kind.rawValue + ":"))
        }
    }

    @Test(
        "Keychain topic store loadAll ignores foreign records that share the service (AUD-032)",
        .enabled(if: realKeychainSessionTopicStoreIsAvailable)
    )
    func keychainTopicStoreLoadAllIgnoresForeignRecords() async throws {
        let service = uniqueKeychainService()
        try deleteAllKeychainTopicRecords(service: service)
        defer { try? deleteAllKeychainTopicRecords(service: service) }

        let store = KeychainWalletSessionTopicStore(service: service)
        try await store.save(topic: "topic-eth", walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum, verified: true)

        // Foreign record 1: the relay-auth identity — raw bytes that are NOT valid
        // UTF-8. Before AUD-032 this made loadAll() throw `.invalidTopicData`.
        var identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: WalletKeychainRecordKind.relayAuthIdentity.rawValue,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: Data([0xff, 0xfe, 0xfd, 0x00, 0x80, 0x81]),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
#if os(macOS)
        identity[kSecUseDataProtectionKeychain as String] = true
#endif
        #expect(SecItemAdd(identity as CFDictionary, nil) == errSecSuccess)

        // Foreign record 2: a per-topic session-state record. Before AUD-032 its
        // account decoded as a bogus topic whose deletion clobbered session state.
        var stateRecord = keychainSessionStateBaseQuery(service: service)
        stateRecord[kSecAttrAccount as String] = WalletKeychainRecordKind.sessionRecord.rawValue + ":deadbeef"
        stateRecord[kSecValueData as String] = Data("{\"any\":\"json\"}".utf8)
        stateRecord[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #expect(SecItemAdd(stateRecord as CFDictionary, nil) == errSecSuccess)

        // loadAll returns ONLY the real topic record, and never throws.
        let all = try await store.loadAll()
        #expect(all == [WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-eth", chain: .ethereum, verified: true)])
    }

    @Test(
        "Keychain topic store migrates a legacy un-namespaced record to the session-topic layout (AUD-032)",
        .enabled(if: realKeychainSessionTopicStoreIsAvailable)
    )
    func keychainTopicStoreMigratesLegacyUnnamespacedRecord() async throws {
        let service = uniqueKeychainService()
        try deleteAllKeychainTopicRecords(service: service)
        defer { try? deleteAllKeychainTopicRecords(service: service) }

        // A legacy record keyed by the bare CAIP-2 address (the pre-AUD-032 layout).
        var legacy: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "eip155:1:0x0000000000000000000000000000000000000000",
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: Data("legacy-topic".utf8),
            kSecAttrLabel as String: WalletChain.ethereum.caip2,
            kSecAttrDescription as String: "1",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
#if os(macOS)
        legacy[kSecUseDataProtectionKeychain as String] = true
#endif
        #expect(SecItemAdd(legacy as CFDictionary, nil) == errSecSuccess)

        // First access triggers the one-shot migration.
        let store = KeychainWalletSessionTopicStore(service: service)
        let all = try await store.loadAll()
        #expect(all == [WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "legacy-topic", chain: .ethereum, verified: true)])
        #expect(try await store.load(walletAddress: "0x0000000000000000000000000000000000000000", chain: .ethereum) == "legacy-topic")
    }

    @Test("WalletConnect URI formats and parses canonical v2 pairing URI")
    func walletConnectURIFormatsAndParses() throws {
        let uri = WalletConnectURI(
            topic: "topic-1",
            symKey: "abc123",
            expiryTimestamp: 1_800_000_000,
            methods: ["wc_sessionPropose"]
        )
        let parsed = try #require(WalletConnectURI(absoluteString: uri.absoluteString))

        #expect(uri.absoluteString == "wc:topic-1@2?symKey=abc123&relay-protocol=irn&expiryTimestamp=1800000000&methods=[wc_sessionPropose]")
        #expect(uri.deeplinkURIValue == "wc%3Atopic-1%402%3FsymKey%3Dabc123%26relay-protocol%3Dirn%26expiryTimestamp%3D1800000000%26methods%3D%5Bwc_sessionPropose%5D")
        #expect(parsed == uri)
    }

    @Test(
        "WalletConnect URI parsing rejects malformed symmetric keys",
        arguments: [
            "wc:topic-1@2?symKey=&relay-protocol=irn",              // empty
            "wc:topic-1@2?symKey=nothex&relay-protocol=irn",         // non-hex chars
            "wc:topic-1@2?symKey=abc&relay-protocol=irn",            // odd length
            "wc:topic-1@2?symKey=ab cd&relay-protocol=irn",          // whitespace
            "wc:topic-1@2?relay-protocol=irn",                       // missing symKey
        ]
    )
    func walletConnectURIRejectsMalformedSymKeys(absoluteString: String) {
        #expect(WalletConnectURI(absoluteString: absoluteString) == nil)
    }

    @Test("WalletConnect URI reports canonical v2 only for full-length hex topic and key")
    func walletConnectURIReportsCanonicalV2() {
        let hexTopic = String(repeating: "b", count: 64)
        let hexKey = String(repeating: "a", count: 64)
        let short = WalletConnectURI(topic: hexTopic, symKey: "abc123", expiryTimestamp: 0)
        let full = WalletConnectURI(topic: hexTopic, symKey: hexKey, expiryTimestamp: 0)
        let emptyTopic = WalletConnectURI(topic: "", symKey: hexKey, expiryTimestamp: 0)
        let shortTopic = WalletConnectURI(topic: "topic-1", symKey: hexKey, expiryTimestamp: 0)
        let nonHexTopic = WalletConnectURI(topic: String(repeating: "g", count: 64), symKey: hexKey, expiryTimestamp: 0)

        #expect(short.isCanonicalV2 == false)
        #expect(full.isCanonicalV2 == true)
        #expect(emptyTopic.isCanonicalV2 == false)
        #expect(shortTopic.isCanonicalV2 == false)
        #expect(nonHexTopic.isCanonicalV2 == false)
    }

    @Test("Provider deep link encodes nested WalletConnect URI once")
    func providerDeepLinkEncodesNestedURIOnce() throws {
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)
        let link = WalletProviderDeepLink(providerID: "metamask", scheme: "metamask://")
        let url = try #require(link.url(pairingURI: uri))

        #expect(url.absoluteString == "metamask://wc?uri=wc%3Atopic-1%402%3FsymKey%3Dabc123%26relay-protocol%3Dirn%26expiryTimestamp%3D1800000000")
    }

    @Test("Provider deep link includes encoded redirect URL when supplied")
    func providerDeepLinkIncludesEncodedRedirectURLWhenSupplied() throws {
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)
        let link = WalletProviderDeepLink(providerID: "metamask", scheme: "metamask://")
        let url = try #require(link.url(pairingURI: uri, redirect: WalletConnectionRedirect(native: "auralis-wcdemo://wc")))

        #expect(url.absoluteString.hasSuffix("&redirectUrl=auralis-wcdemo%3A%2F%2Fwc"))
    }

    @Test("Return URL handler separates foreground and future Link Mode callbacks")
    func returnURLHandlerSeparatesCallbackKinds() throws {
        let handler = WalletReturnURLHandler()

        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://wc"))) == .foreground)
        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://callback?wc_ev=envelope"))) == .linkModeEnvelope("envelope"))
        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://unrelated"))) == nil)
    }

    @Test("Return URL handler rejects callbacks outside configured schemes and hosts")
    func returnURLHandlerRejectsCallbacksOutsideConfiguredSchemesAndHosts() throws {
        let handler = WalletReturnURLHandler(
            allowedSchemes: ["auralis-wcdemo"],
            allowedHosts: ["wc", "callback"]
        )

        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://wc"))) == .foreground)
        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://callback?wc_ev=envelope"))) == .linkModeEnvelope("envelope"))
        #expect(handler.handle(try #require(URL(string: "other-app://wc"))) == nil)
        #expect(handler.handle(try #require(URL(string: "auralis-wcdemo://unrelated?wc_ev=envelope"))) == nil)
    }

    @Test("Inbound URL coordinator queues cold launch callbacks and suppresses duplicates")
    func inboundURLCoordinatorQueuesColdLaunchCallbacksAndSuppressesDuplicates() async throws {
        let coordinator = WalletInboundURLCoordinator(
            handler: WalletReturnURLHandler(allowedSchemes: ["auralis-wcdemo"], allowedHosts: ["wc"])
        )
        let callback = try #require(URL(string: "auralis-wcdemo://wc"))

        #expect(await coordinator.capture(callback, isReady: false) == nil)
        #expect(await coordinator.capture(callback, isReady: false) == nil)
        #expect(await coordinator.drainQueuedPayloads() == [.foreground])
        #expect(await coordinator.drainQueuedPayloads().isEmpty)
    }

    @Test("Inbound URL coordinator returns ready callbacks immediately")
    func inboundURLCoordinatorReturnsReadyCallbacksImmediately() async throws {
        let coordinator = WalletInboundURLCoordinator()
        let callback = try #require(URL(string: "auralis-wcdemo://callback?wc_ev=envelope"))

        #expect(await coordinator.capture(callback, isReady: true) == .linkModeEnvelope("envelope"))
        #expect(await coordinator.drainQueuedPayloads().isEmpty)
    }

    @Test("Inbound URL coordinator rejects callbacks for the wrong pending operation")
    func inboundURLCoordinatorRejectsWrongPendingOperation() async throws {
        let coordinator = WalletInboundURLCoordinator(
            handler: WalletReturnURLHandler(allowedSchemes: ["auralis-wcdemo"], allowedHosts: ["wc"])
        )
        await coordinator.registerExpectation(WalletCallbackExpectation(operationID: "expected-request"))
        let wrong = try #require(URL(string: "auralis-wcdemo://wc?state=wrong-request"))
        let expected = try #require(URL(string: "auralis-wcdemo://wc?state=expected-request"))

        #expect(await coordinator.capture(wrong, isReady: true) == nil)
        #expect(await coordinator.capture(expected, isReady: true) == .foreground)
    }

    @Test("Inbound URL coordinator deduplicates callbacks that differ only in query order")
    func inboundURLCoordinatorDeduplicatesReorderedQueries() async throws {
        let coordinator = WalletInboundURLCoordinator(
            handler: WalletReturnURLHandler(allowedSchemes: ["auralis-wcdemo"], allowedHosts: ["wc"])
        )
        let first = try #require(URL(string: "auralis-wcdemo://wc?a=1&b=2"))
        let reordered = try #require(URL(string: "auralis-wcdemo://wc?b=2&a=1"))

        #expect(await coordinator.capture(first, isReady: true) == .foreground)
        #expect(await coordinator.capture(reordered, isReady: true) == nil)
    }

    @Test("Inbound URL coordinator bounds registered expectations, evicting oldest-first")
    func inboundURLCoordinatorBoundsExpectations() async throws {
        let coordinator = WalletInboundURLCoordinator(
            handler: WalletReturnURLHandler(allowedSchemes: ["auralis-wcdemo"], allowedHosts: ["wc"]),
            maxExpectations: 2
        )
        // Register three expectations *without* an expiry (the expiry sweep never
        // prunes these), exceeding the cap of two so the oldest is evicted.
        for op in ["op-1", "op-2", "op-3"] {
            await coordinator.registerExpectation(WalletCallbackExpectation(operationID: op))
        }

        // op-1 was evicted: its callback no longer matches a pending expectation.
        let evicted = try #require(URL(string: "auralis-wcdemo://wc?state=op-1"))
        #expect(await coordinator.capture(evicted, isReady: true) == nil)
        // op-3 (the newest) is still registered and matches.
        let retained = try #require(URL(string: "auralis-wcdemo://wc?state=op-3"))
        #expect(await coordinator.capture(retained, isReady: true) == .foreground)
    }
}

@Suite("Wallet connection presentation")
struct WalletConnectionPresentationTests {
    @Test("Pairing presentation defaults QR payload to WalletConnect URI")
    func pairingPresentationDefaultsQRPayload() {
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)
        let presentation = WalletPairingPresentation(
            provider: WalletConnectorCatalog.metamask,
            pairingURI: uri,
            expiryDate: .sampleDate
        )

        #expect(presentation.id == "topic-1")
        #expect(presentation.qrPayload == uri.absoluteString)
        #expect(presentation.state == .pairing)
    }

    @Test("WalletConnect protocol state refuses topic-only restoration")
    func walletConnectProtocolStateRefusesTopicOnlyRestoration() {
        let topicOnly = WalletConnectProtocolState(
            pairingTopic: "pairing-topic",
            pairingSymmetricKey: nil,
            pairingExpiryDate: .sampleDate
        )
        let restorable = WalletConnectProtocolState(
            pairingTopic: "pairing-topic",
            pairingSymmetricKey: "pairing-key",
            pairingExpiryDate: .sampleDate.addingTimeInterval(300),
            sessionTopic: "session-topic",
            sessionSymmetricKey: "session-key",
            sessionExpiryDate: .sampleDate.addingTimeInterval(600),
            relayClientID: "did:key:zRelay",
            relayIdentityPublicKey: "relay-public-key",
            subscribedTopics: ["session-topic"],
            namespaces: []
        )

        #expect(topicOnly.restorationStatus == .missingPairingSymmetricKey)
        #expect(!topicOnly.restorationStatus.canResumeSession)
        #expect(restorable.restorationStatus == .restorableSession("session-topic"))
        #expect(restorable.restorationStatus.canResumeSession)
    }

    @Test("SDK error mapper normalizes common provider messages")
    func sdkErrorMapperNormalizesCommonMessages() {
        #expect(WalletSDKErrorMapper.connectionError(message: "User rejected request") == .userRejected)
        #expect(WalletSDKErrorMapper.connectionError(providerID: "metamask", message: "Wallet not installed") == .walletNotInstalled("metamask"))
        #expect(WalletSDKErrorMapper.connectionError(context: WalletProviderErrorContext(providerID: "coinbase-wallet", code: 4001, message: "User denied", underlyingType: "CoinbaseWalletSDKError")) == .userRejected)
        #expect(WalletSDKErrorMapper.failure(code: 4001, message: "Rejected").code == 4001)
    }
}

@Suite("Reown adapter")
struct ReownAdapterTests {
    @Test("Unconfigured Reown client reports typed unavailable errors")
    func unconfiguredReownClientReportsUnavailableErrors() async throws {
        let client = UnconfiguredReownAppKitClient(message: "not configured")
        let request = WalletRequest(
            id: "request-1",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethPersonalSign,
            params: ["Hello", "0x0000000000000000000000000000000000000000"],
            expiryDate: .sampleDate
        )

        await #expect(throws: WalletConnectionError.unavailable("not configured")) {
            _ = try await client.connect(proposalRequest: .defaultV1Optional, wallet: nil)
        }
        await #expect(throws: WalletConnectionError.unavailable("not configured")) {
            _ = try await client.sessions()
        }
        await #expect(throws: WalletConnectionError.unavailable("not configured")) {
            try await client.disconnect(sessionId: "topic-1")
        }
        await #expect(throws: WalletConnectionError.unavailable("not configured")) {
            _ = try await client.request(request, in: "topic-1")
        }
        await #expect(throws: WalletConnectionError.unavailable("not configured")) {
            try await client.handleCallback(url: URL(string: "auralis-wcdemo://wc")!)
        }
    }

    @Test("Reown wallet connector forwards calls to injected client")
    func reownWalletConnectorForwardsCalls() async throws {
        let client = RecordingReownAppKitClient()
        let connector = ReownWalletConnector(client: client)
        let request = WalletRequest(
            id: "request-1",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethPersonalSign,
            params: ["Hello", "0x0000000000000000000000000000000000000000"],
            expiryDate: .sampleDate
        )

        let start = try await connector.connect(proposal: .defaultV1, wallet: WalletConnectorCatalog.metamask)
        try await connector.handleCallback(url: URL(string: "auralis-wcdemo://wc")!)
        let sessions = try await connector.sessions()
        try await connector.disconnect(sessionId: "topic-1")
        let response = try await connector.request(request, in: "topic-1")

        #expect(start.qrPayload == "wc:topic-1@2")
        #expect(sessions == [.sampleSession])
        #expect(response == WalletResponse(id: "request-1", result: "approved"))
        #expect(await client.connectWalletIDs() == ["metamask"])
        #expect(await client.handledCallbackURLs().map(\.absoluteString) == ["auralis-wcdemo://wc"])
        #expect(await client.disconnectedSessionIDs() == ["topic-1"])
        #expect(await client.requestedSessionIDs() == ["topic-1"])
    }

    @Test("Reown wallet connector verifies ownership through personal_sign")
    func reownWalletConnectorVerifiesOwnershipThroughPersonalSign() async throws {
        let publicKey = Data((0..<64).map { UInt8($0) })
        let expectedAddress = "0x" + EthereumKeccak256.hash(publicKey).suffix(20).map { String(format: "%02x", $0) }.joined()
        let client = RecordingReownAppKitClient(responseResult: Self.validSignatureHex)
        let connector = ReownWalletConnector(
            client: client,
            cryptoProvider: FixedRecoveryCryptoProvider(publicKey: publicKey),
            metadata: .testValue
        )

        let verified = try await connector.verifyOwnership(
            of: expectedAddress,
            in: "topic-1",
            statement: "Verify test ownership.",
            expiryDate: Date().addingTimeInterval(300)
        )

        #expect(verified)
        let request = try #require(await client.requestedRequests().first)
        #expect(request.method == .ethPersonalSign)
        #expect(request.params.last?.stringValue == expectedAddress)
        let message = try Self.personalSignMessage(from: request)
        #expect(message.contains("auralis.example wants you to sign in with your Ethereum account:"))
        #expect(message.contains(expectedAddress))
        #expect(message.contains("URI: https://auralis.example"))
        #expect(message.contains("Chain ID: 1"))
        #expect(message.contains("Nonce: "))
        #expect(message.contains("Issued At: "))
        #expect(message.contains("Expiration Time: "))
    }

    @Test("Coinbase wallet connector verifies ownership through client request")
    func coinbaseWalletConnectorVerifiesOwnershipThroughClientRequest() async throws {
        let publicKey = Data((0..<64).map { UInt8($0) })
        let expectedAddress = "0x" + EthereumKeccak256.hash(publicKey).suffix(20).map { String(format: "%02x", $0) }.joined()
        let client = RecordingCoinbaseWalletSDKClient(responseResult: Self.validSignatureHex)
        let connector = CoinbaseWalletConnector(
            client: client,
            cryptoProvider: FixedRecoveryCryptoProvider(publicKey: publicKey),
            metadata: .testValue
        )

        let verified = try await connector.verifyOwnership(
            of: expectedAddress,
            in: "coinbase-1",
            statement: "Verify test ownership.",
            expiryDate: Date().addingTimeInterval(300)
        )

        #expect(verified)
        let request = try #require(await client.requestedRequests().first)
        #expect(request.method == .ethPersonalSign)
        #expect(request.params.last?.stringValue == expectedAddress)
        let message = try Self.personalSignMessage(from: request)
        #expect(message.contains("auralis.example wants you to sign in with your Ethereum account:"))
        #expect(message.contains(expectedAddress))
        #expect(message.contains("URI: https://auralis.example"))
        #expect(message.contains("Chain ID: 1"))
        #expect(message.contains("Nonce: "))
        #expect(message.contains("Issued At: "))
        #expect(message.contains("Expiration Time: "))
    }

    @Test("Configured SDK connectors require a recovery provider and real metadata before production readiness")
    func sdkConnectorReadinessRequiresOwnershipDependencies() {
        let recovery = FixedRecoveryCryptoProvider(publicKey: Data(repeating: 1, count: 64))

        // Configured client but the default (non-recovery) provider → experimental.
        let reownDefault = ReownWalletConnector(client: RecordingReownAppKitClient(responseResult: ""))
        #expect(reownDefault.readiness.allowsProductionUse == false)
        let coinbaseDefault = CoinbaseWalletConnector(client: RecordingCoinbaseWalletSDKClient(responseResult: ""))
        #expect(coinbaseDefault.readiness.allowsProductionUse == false)

        // Recovery provider but no explicit production metadata → still experimental.
        let reownNoMetadata = ReownWalletConnector(
            client: RecordingReownAppKitClient(responseResult: ""),
            cryptoProvider: recovery
        )
        #expect(reownNoMetadata.readiness.allowsProductionUse == false)

        // Recovery provider + real metadata → production ready.
        let reownReady = ReownWalletConnector(
            client: RecordingReownAppKitClient(responseResult: ""),
            cryptoProvider: recovery,
            metadata: .testValue
        )
        #expect(reownReady.readiness.allowsProductionUse == true)
        let coinbaseReady = CoinbaseWalletConnector(
            client: RecordingCoinbaseWalletSDKClient(responseResult: ""),
            cryptoProvider: recovery,
            metadata: .testValue
        )
        #expect(coinbaseReady.readiness.allowsProductionUse == true)
    }

    private static func personalSignMessage(from request: WalletRequest) throws -> String {
        let hex = try #require(request.params.first?.stringValue)
        let messageData = try #require(WalletConnectV2Crypto.data(hexEncoded: String(hex.dropFirst(2))))
        return try #require(String(data: messageData, encoding: .utf8))
    }

    private static let validSignatureHex = "0x" + String(repeating: "11", count: 64) + "1b"

    @Test("Reown pending request store resolves responses by request ID")
    func reownPendingRequestStoreResolvesByRequestID() async throws {
        let store = ReownPendingRequestStore()
        let first = WalletRequest(
            id: "request-1",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethPersonalSign,
            params: ["Hello", "0x0000000000000000000000000000000000000000"],
            expiryDate: .sampleDate
        )
        let second = WalletRequest(
            id: "request-2",
            chain: WalletBlockchain(namespace: "eip155", reference: "1"),
            method: .ethPersonalSign,
            params: ["Hello", "0x0000000000000000000000000000000000000000"],
            expiryDate: .sampleDate
        )
        let firstTask = Task { try await store.wait(for: first) }
        let secondTask = Task { try await store.wait(for: second) }

        while await Set(store.pendingRequestIDs()) != Set(["request-1", "request-2"]) {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        await store.resolve(WalletResponse(id: "request-2", result: "second"))
        await store.resolve(WalletResponse(id: "request-1", result: "first"))

        #expect(try await firstTask.value == WalletResponse(id: "request-1", result: "first"))
        #expect(try await secondTask.value == WalletResponse(id: "request-2", result: "second"))
        #expect(await store.pendingRequestIDs().isEmpty)
    }

    @Test("Reown pending request store correlates by the on-the-wire JSON-RPC id, not the caller id")
    func reownPendingRequestStoreCorrelatesByWireID() async throws {
        let store = ReownPendingRequestStore()
        // The wire id (assigned by the SDK) differs from the caller's request id.
        let wireID: WalletSignRequestID = "1721000000000000123"
        let waiter = Task { try await store.wait(id: wireID, expiryDate: .distantFuture) }

        while await store.pendingRequestIDs() != [wireID] {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        await store.resolve(WalletResponse(id: wireID, result: "0xsignature"))
        #expect(try await waiter.value == WalletResponse(id: wireID, result: "0xsignature"))
        #expect(await store.pendingRequestIDs().isEmpty)
    }

    @Test("Reown pending request store buffers responses that arrive before the waiter registers")
    func reownPendingRequestStoreBuffersEarlyResponses() async throws {
        let store = ReownPendingRequestStore()
        let wireID: WalletSignRequestID = "1721000000000000456"

        // Response lands first (submit/response race); the later waiter must still
        // receive it rather than hang until expiry.
        await store.resolve(WalletResponse(id: wireID, result: "0xearly"))
        #expect(try await store.wait(id: wireID, expiryDate: .distantFuture) == WalletResponse(id: wireID, result: "0xearly"))
    }

    @Test("Reown pending request store fails the waiter on an error response")
    func reownPendingRequestStoreFailsOnErrorResponse() async throws {
        let store = ReownPendingRequestStore()
        let wireID: WalletSignRequestID = "1721000000000000789"
        let waiter = Task { try await store.wait(id: wireID, expiryDate: .distantFuture) }

        while await store.pendingRequestIDs() != [wireID] {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        await store.fail(wireID, error: WalletConnectionError.userRejected)
        await #expect(throws: WalletConnectionError.userRejected) {
            _ = try await waiter.value
        }
    }

    #if os(iOS)
    @Test("Reown AppKit configuration validates project ID and configures only once")
    @MainActor
    func reownAppKitConfigurationValidatesAndConfiguresOnce() throws {
        let crypto = FakeReownCryptoProvider()
        var configuredProjectIDs: [String] = []
        ReownAppKitConfiguration.resetForTesting()
        defer { ReownAppKitConfiguration.resetForTesting() }
        ReownAppKitConfiguration.configureDriver = { projectID, _, _, _ in
            configuredProjectIDs.append(projectID)
        }

        #expect(throws: WalletConnectionError.unavailable("REOWN_PROJECT_ID not set - see README.md")) {
            try ReownAppKitConfiguration.configureOnce(projectID: "   ", crypto: crypto)
        }

        try ReownAppKitConfiguration.configureOnce(projectID: " project-1 ", crypto: crypto)
        try ReownAppKitConfiguration.configureOnce(projectID: "project-1", crypto: crypto)

        #expect(configuredProjectIDs == ["project-1"])
        #expect(throws: WalletConnectionError.unavailable("Reown AppKit is already configured with different metadata or project ID.")) {
            try ReownAppKitConfiguration.configureOnce(projectID: "project-2", crypto: crypto)
        }
    }
    #endif
}

@Suite("Wallet connection core")
struct WalletConnectionCoreTests {
    @Test("Deep-link launcher opens installed wallet")
    func deepLinkLauncherOpensInstalledWallet() async throws {
        let opener = RecordingWalletOpener(canOpen: true, openResult: true)
        let launcher = DeepLinkWalletLauncher(opener: opener)
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)

        try await launcher.launch(provider: WalletConnectorCatalog.metamask, pairingURI: uri)

        #expect(await opener.openedURLs().map(\.absoluteString) == [
            "metamask://wc?uri=wc%3Atopic-1%402%3FsymKey%3Dabc123%26relay-protocol%3Dirn%26expiryTimestamp%3D1800000000",
        ])
    }

    @Test("Deep-link launcher reports wallet not installed")
    func deepLinkLauncherReportsMissingWallet() async {
        let opener = RecordingWalletOpener(canOpen: false, openResult: false)
        let launcher = DeepLinkWalletLauncher(opener: opener)
        let uri = WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000)

        await #expect(throws: WalletConnectionError.walletNotInstalled("metamask")) {
            try await launcher.launch(provider: WalletConnectorCatalog.metamask, pairingURI: uri)
        }
    }

    @Test("DApp connector creates pairing and opens selected wallet through injected boundary")
    func dAppConnectorCreatesPairingAndOpensWallet() async throws {
        let opener = RecordingWalletOpener(canOpen: true, openResult: true)
        let transport = FakeWalletTransport()
        let connector = WalletConnectDAppConnector(
            transport: transport,
            launcher: DeepLinkWalletLauncher(opener: opener),
            metadata: .testValue,
            callbackURL: URL(string: "auralis-wcdemo://wc")
        )

        let start = try await connector.connect(
            proposal: .defaultV1,
            wallet: WalletConnectorCatalog.rainbow
        )

        #expect(start.qrPayload == start.pairingURI?.absoluteString)
        #expect(start.walletOpenURL?.scheme == "rainbow")
        #expect(await transport.pairingRequests().first?.providerID == "rainbow")
        #expect(await opener.openedURLs().first?.scheme == "rainbow")
    }

    @Test("DApp connector readiness is gated on ownership dependencies by default")
    func dAppConnectorReadinessIsGatedOnOwnershipDependenciesByDefault() {
        let defaultConnector = WalletConnectDAppConnector(
            transport: FakeWalletTransport(),
            metadata: .testValue
        )
        let recoveryConnector = WalletConnectDAppConnector(
            transport: FakeWalletTransport(),
            metadata: .testValue,
            cryptoProvider: FixedRecoveryCryptoProvider(publicKey: Data(repeating: 1, count: 64))
        )
        let overrideConnector = WalletConnectDAppConnector(
            transport: FakeWalletTransport(),
            metadata: .testValue,
            readiness: .productionReady
        )

        #expect(defaultConnector.runtimeFamily == .customWalletConnectIRN)
        #expect(defaultConnector.readiness.allowsProductionUse == false)
        guard case .experimental = defaultConnector.readiness else {
            Issue.record("expected .experimental, got \(defaultConnector.readiness)")
            return
        }
        #expect(recoveryConnector.readiness.allowsProductionUse == true)
        #expect(overrideConnector.readiness.allowsProductionUse == true)
    }

    @Test("Wallet connector readiness defaults to unavailable without an override")
    func walletConnectorReadinessDefaultsToUnavailableWithoutOverride() async {
        let connector: any WalletConnector = FakeSessionWalletConnector(sessions: [])

        #expect(connector.runtimeFamily == .providerSDK)
        #expect(connector.readiness.allowsProductionUse == false)
        guard case .unavailable = connector.readiness else {
            Issue.record("expected .unavailable, got \(connector.readiness)")
            return
        }
    }

    @Test("In-memory session store saves loads lists and deletes sessions")
    func inMemorySessionStoreRoundTrips() async throws {
        let store = InMemoryWalletSessionStore()
        let record = WalletSessionRecord(session: .sampleSession, savedAt: .sampleDate)

        await store.save(record)

        #expect(await store.load(sessionID: "topic-1") == record)
        #expect(await store.loadAll() == [record])

        await store.delete(sessionID: "topic-1")
        #expect(await store.loadAll().isEmpty)
    }

    @Test("Session address extractor filters unsupported accounts and deduplicates by chain and address")
    func sessionAddressExtractorFiltersAndDeduplicates() throws {
        let session = WalletConnectorSession(
            id: "topic-1",
            topic: "topic-1",
            providerID: "generic",
            providerName: "Generic Wallet",
            accounts: [
                WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000"),
                WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000"),
                WalletAccount(caip10: "eip155:999:0x1111111111111111111111111111111111111111"),
                WalletAccount(caip10: "solana:mainnet:11111111111111111111111111111111"),
            ],
            namespaces: [],
            expiryDate: .sampleDate
        )

        let addresses = WalletSessionAddressExtractor.extract(from: session)

        #expect(addresses.map(\.chain) == [.ethereum, .solana])
        #expect(addresses.map(\.account.caip10) == [
            "eip155:1:0x0000000000000000000000000000000000000000",
            "solana:mainnet:11111111111111111111111111111111",
        ])
    }

    @Test("In-memory active wallet store round-trips selection")
    func inMemoryActiveWalletStoreRoundTrips() {
        let store = InMemoryActiveWalletStore()

        #expect(store.get() == nil)
        store.set("0x0000000000000000000000000000000000000000")
        #expect(store.get() == "0x0000000000000000000000000000000000000000")
        store.clear()
        #expect(store.get() == nil)
    }

    @Test("Keychain query factory uses foreground-only device-only storage and disables synchronization")
    func keychainQueryFactoryUsesRequiredSecurityAttributes() {
        let factory = KeychainSessionTopicQueryFactory(service: "test.service")
        let query = factory.addQuery(
            walletAddress: "0x0000000000000000000000000000000000000000",
            topicData: Data("topic-1".utf8)
        )

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "test.service")
        // AUD-032: topic records are namespaced with the `session-topic:` prefix so
        // they never collide with the relay-auth identity or the per-topic
        // session-state records that share this keychain service.
        #expect(query[kSecAttrAccount as String] as? String == "session-topic:0x0000000000000000000000000000000000000000")
        #expect(query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(KeychainSessionTopicQueryFactory(service: "test.service").allItemsQuery()[kSecReturnData as String] == nil)
        #expect(WalletKeychainRecordDescriptor(kind: .sessionSymmetricKey, identifier: "topic-1").accountKey == "session-symmetric-key:topic-1")
    }

    @Test("Relay configuration appends project ID query item")
    func relayConfigurationAppendsProjectID() throws {
        let configuration = WalletConnectRelayConfiguration(
            projectID: "project-1",
            relayURL: try #require(URL(string: "wss://relay.walletconnect.com"))
        )

        #expect(configuration.websocketURL.absoluteString == "wss://relay.walletconnect.com?projectId=project-1")
    }

    @Test("IRN relay client sends subscribe and publish JSON-RPC messages")
    func irnRelayClientSendsSubscribeAndPublish() async throws {
        let task = RecordingRelayTask(
            receiveMessages: [
                #"{"id":1,"jsonrpc":"2.0","result":{"messages":[],"hasMore":false}}"#,
                #"{"id":2,"jsonrpc":"2.0","result":"subscription-topic-1"}"#,
                #"{"id":3,"jsonrpc":"2.0","result":true}"#,
            ],
            receiveGates: [1, 2, 3]
        )
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )
        defer { Task { await client.disconnect() } }

        try await client.subscribe(topic: "topic-1")
        try await client.publish(
            WalletConnectRelayPublish(
                topic: "topic-1",
                message: "encrypted-message",
                tag: 1100,
                ttl: 300
            )
        )

        let sent = await task.sentMessages()
        #expect(sent.count == 3)
        #expect(sent[0].contains(#""method":"irn_fetchMessages""#))
        #expect(sent[0].contains(#""topic":"topic-1""#))
        #expect(sent[1].contains(#""method":"irn_subscribe""#))
        #expect(sent[1].contains(#""topic":"topic-1""#))
        #expect(sent[2].contains(#""method":"irn_publish""#))
        #expect(sent[2].contains(#""message":"encrypted-message""#))
        #expect(sent[2].contains(#""tag":1100"#))
    }

    @Test("IRN relay client accepts non-boolean subscribe acknowledgements")
    func irnRelayClientAcceptsStringSubscribeAck() async throws {
        // A real relay acks `irn_subscribe` with a subscription-id *string*, not
        // `true`. Decoding this must be treated as success rather than dropped
        // (which previously stalled the subscribe until the ack timeout).
        let task = RecordingRelayTask(
            receiveMessages: [
                #"{"id":1,"jsonrpc":"2.0","result":{"messages":[],"hasMore":false}}"#,
                #"{"id":2,"jsonrpc":"2.0","result":"a1b2c3subscriptionid"}"#,
            ],
            receiveGates: [1, 2]
        )
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )
        defer { Task { await client.disconnect() } }

        try await client.subscribe(topic: "topic-1")

        let sent = await task.sentMessages()
        #expect(sent.count == 2)
        #expect(sent[0].contains(#""method":"irn_fetchMessages""#))
        #expect(sent[1].contains(#""method":"irn_subscribe""#))
    }

    @Test("IRN relay client unsubscribes with the relay subscription id")
    func irnRelayClientUnsubscribesWithSubscriptionID() async throws {
        let task = RecordingRelayTask(
            receiveMessages: [
                #"{"id":1,"jsonrpc":"2.0","result":{"messages":[],"hasMore":false}}"#,
                #"{"id":2,"jsonrpc":"2.0","result":"subscription-topic-1"}"#,
                #"{"id":3,"jsonrpc":"2.0","result":true}"#,
            ],
            receiveGates: [1, 2, 3]
        )
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )
        defer { Task { await client.disconnect() } }

        try await client.subscribe(topic: "topic-1")
        await client.unsubscribe(topic: "topic-1")

        let sent = try await task.waitForSentCount(3)
        #expect(sent[2].contains(#""method":"irn_unsubscribe""#))
        #expect(sent[2].contains(#""topic":"topic-1""#))
        #expect(sent[2].contains(#""id":"subscription-topic-1""#))
    }

    @Test("IRN relay client surfaces subscription events")
    func irnRelayClientSurfacesSubscriptionEvents() async throws {
        let task = RecordingRelayTask(
            receiveMessages: [
                #"{"id":1,"jsonrpc":"2.0","result":{"messages":[],"hasMore":false}}"#,
                #"{"id":2,"jsonrpc":"2.0","result":"subscription-topic-1"}"#,
                #"{"id":99,"jsonrpc":"2.0","method":"irn_subscription","params":{"data":{"topic":"topic-1","message":"payload","tag":1101}}}"#,
            ],
            receiveGates: [1, 2, 2]
        )
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )
        defer { Task { await client.disconnect() } }

        var iterator = client.events.makeAsyncIterator()
        try await client.subscribe(topic: "topic-1")

        var observedSubscription: WalletConnectRelayEvent?
        for _ in 0..<4 {
            guard let event = await iterator.next() else { break }
            if case .subscription = event {
                observedSubscription = event
                break
            }
        }

        let sent = try await task.waitForSentCount(3)
        #expect(observedSubscription == .subscription(topic: "topic-1", message: "payload", tag: 1101))
        #expect(sent[2].contains(#"id":99"#))
        #expect(sent[2].contains(#"result":true"#))
    }

    @Test("IRN relay client drains fetch messages pages before subscribing")
    func irnRelayClientDrainsFetchMessagesPagesBeforeSubscribe() async throws {
        let task = RecordingRelayTask(
            receiveMessages: [
                #"{"id":1,"jsonrpc":"2.0","result":{"messages":[{"topic":"topic-1","message":"queued-1","tag":1109}],"hasMore":true}}"#,
                #"{"id":2,"jsonrpc":"2.0","result":{"messages":[{"topic":"topic-1","message":"queued-2","tag":1112}],"hasMore":false}}"#,
                #"{"id":3,"jsonrpc":"2.0","result":"subscription-topic-1"}"#,
            ],
            receiveGates: [1, 2, 3]
        )
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )
        defer { Task { await client.disconnect() } }
        var iterator = client.events.makeAsyncIterator()

        try await client.subscribe(topic: "topic-1")

        let first = await iterator.next()
        let second = await iterator.next()
        let sent = try await task.waitForSentCount(3)
        #expect(first == .socketStatusChanged(.connecting))
        #expect(second == .socketStatusChanged(.connected))
        var fetched: [WalletConnectRelayEvent] = []
        for _ in 0..<2 {
            if let event = await iterator.next() {
                fetched.append(event)
            }
        }
        #expect(fetched.contains(.subscription(topic: "topic-1", message: "queued-1", tag: 1109)))
        #expect(fetched.contains(.subscription(topic: "topic-1", message: "queued-2", tag: 1112)))
        #expect(sent[0].contains(#""method":"irn_fetchMessages""#))
        #expect(sent[1].contains(#""method":"irn_fetchMessages""#))
        #expect(sent[2].contains(#""method":"irn_subscribe""#))
    }

    @Test("IRN relay client sends fetch messages request for reconnect recovery")
    func irnRelayClientSendsFetchMessagesRequest() async throws {
        let task = RecordingRelayTask(
            receiveMessages: [
                #"{"id":1,"jsonrpc":"2.0","result":true}"#,
            ],
            receiveGates: [1]
        )
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )
        defer { Task { await client.disconnect() } }

        try await client.fetchMessages(topic: "topic-1")

        let sent = await task.sentMessages()
        #expect(sent.count == 1)
        #expect(sent[0].contains(#""method":"irn_fetchMessages""#))
        #expect(sent[0].contains(#""topic":"topic-1""#))
    }

    @Test("IRN relay client fails publish when relay rejects acknowledgement")
    func irnRelayClientFailsPublishWhenRelayRejectsAcknowledgement() async throws {
        let task = RecordingRelayTask(
            receiveMessages: [
                #"{"id":1,"jsonrpc":"2.0","error":{"code":-32000,"message":"rejected"}}"#,
            ],
            receiveGates: [1]
        )
        let client = WalletConnectIRNRelayClient(
            configuration: WalletConnectRelayConfiguration(projectID: "project-1"),
            taskFactory: FixedRelayTaskFactory(task: task)
        )
        defer { Task { await client.disconnect() } }

        await #expect(throws: WalletConnectionError.relayAcknowledgementFailed("rejected")) {
            try await client.publish(
                WalletConnectRelayPublish(
                    topic: "topic-1",
                    message: "encrypted-message",
                    tag: 1108,
                    ttl: 300
                )
            )
        }
    }

    @Test("Lifecycle service persists settled sessions and selects the newest address")
    func lifecyclePersistsSettledSession() async throws {
        let accountStore = RecordingWalletAccountStore()
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        let metadataResolver = RecordingWalletMetadataResolver()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            metadataResolver: metadataResolver,
            ownershipPolicy: .allowUnverified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        let result = try await service.persistApprovedSession(.multiAccountSession)

        #expect(result.persistedAddresses.map(\.account.address) == [
            "0x0000000000000000000000000000000000000000",
            "11111111111111111111111111111111",
        ])
        #expect(activeStore.get() == "11111111111111111111111111111111")
        #expect(try await topicStore.load(walletAddress: "0x0000000000000000000000000000000000000000") == "topic-1")
        #expect(await accountStore.upserted().count == 2)
        #expect(await metadataResolver.refreshed().count == 2)
    }

    @Test("Lifecycle ownership policy defaults to rejecting unverified sessions")
    func lifecycleOwnershipPolicyDefaultsToRejectUnverifiedSessions() async throws {
        let accountStore = RecordingWalletAccountStore()
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        await #expect(throws: WalletConnectionError.self) {
            _ = try await service.persistApprovedSession(.sampleSession)
        }

        #expect(await accountStore.upserted().isEmpty)
    }

    @Test("Lifecycle strict ownership policy rejects unverified sessions")
    func lifecycleStrictOwnershipPolicyRejectsUnverifiedSessions() async throws {
        let accountStore = RecordingWalletAccountStore()
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            ownershipPolicy: .requireVerified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        await #expect(throws: WalletConnectionError.self) {
            _ = try await service.persistApprovedSession(.sampleSession)
        }

        #expect(await accountStore.upserted().isEmpty)
        #expect(try await topicStore.loadAll().isEmpty)
        #expect(activeStore.get() == nil)
    }

    @Test("Lifecycle strict ownership policy asks connector to verify unverified sessions before persisting")
    func lifecycleStrictOwnershipPolicyVerifiesBeforePersisting() async throws {
        let accountStore = RecordingWalletAccountStore()
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        let connector = FakeSessionWalletConnector(sessions: [], verifiesOwnership: true)
        let service = WalletConnectionLifecycleService(
            connector: connector,
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            ownershipPolicy: .requireVerified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        _ = try await service.persistApprovedSession(.sampleSession)

        #expect(await connector.ownershipCheckAddresses() == ["0x0000000000000000000000000000000000000000"])
        #expect(await accountStore.upserted().map(\.account.address) == ["0x0000000000000000000000000000000000000000"])
        #expect(try await topicStore.loadAll().map(\.address) == ["0x0000000000000000000000000000000000000000"])
        #expect(activeStore.get() == "0x0000000000000000000000000000000000000000")
    }

    @Test("Lifecycle strict ownership policy persists verified sessions")
    func lifecycleStrictOwnershipPolicyPersistsVerifiedSessions() async throws {
        let accountStore = RecordingWalletAccountStore()
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            ownershipPolicy: .requireVerified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )
        let sample = WalletConnectorSession.sampleSession
        let verified = WalletConnectorSession(
            id: sample.id,
            topic: sample.topic,
            providerID: sample.providerID,
            providerName: sample.providerName,
            accounts: sample.accounts,
            namespaces: sample.namespaces,
            expiryDate: sample.expiryDate,
            addressVerified: true
        )

        _ = try await service.persistApprovedSession(verified)

        #expect(await accountStore.upserted().count == 1)
    }

    @Test("Lifecycle service restores live sessions and removes expired saved topics")
    func lifecycleRestoresLiveSessionsAndDeletesExpiredTopics() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-1"),
            WalletSessionTopicRecord(address: "0xffffffffffffffffffffffffffffffffffffffff", topic: "expired-topic"),
        ])
        let activeStore = InMemoryActiveWalletStore()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: [.sampleSession]),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            ownershipPolicy: .allowUnverified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        let result = try await service.restoreSavedSessions()

        #expect(result.persistedAddresses.map(\.account.address) == ["0x0000000000000000000000000000000000000000"])
        #expect(activeStore.get() == "0x0000000000000000000000000000000000000000")
        #expect(result.removedSessionTopics == [
            WalletSessionTopicRecord(address: "0xffffffffffffffffffffffffffffffffffffffff", topic: "expired-topic"),
        ])
        #expect(try await topicStore.load(walletAddress: "0xffffffffffffffffffffffffffffffffffffffff") == nil)
        #expect(await accountStore.deactivated().map(\.address) == ["0xffffffffffffffffffffffffffffffffffffffff"])
    }

    @Test("Lifecycle strict restore leaves unverified sessions inactive")
    func lifecycleStrictRestoreLeavesUnverifiedSessionsInactive() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topic = WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-1")
        let topicStore = InMemoryWalletSessionTopicStore(records: [topic])
        let activeStore = InMemoryActiveWalletStore(address: "0x0000000000000000000000000000000000000000")
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: [.sampleSession]),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        let result = try await service.restoreSavedSessions()

        #expect(result.persistedAddresses.isEmpty)
        #expect(result.removedSessionTopics.isEmpty)
        #expect(result.unverifiedSessionTopics == [topic])
        #expect(try await topicStore.load(walletAddress: topic.address) == topic.topic)
        #expect(await accountStore.upserted().isEmpty)
        #expect(await accountStore.deactivated().isEmpty)
        #expect(activeStore.get() == nil)
    }

    @Test("Lifecycle strict restore merges a persisted ownership proof so SDK sessions stay active")
    func lifecycleStrictRestoreMergesPersistedOwnershipProof() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        // The live session reports addressVerified == false (an SDK connector's
        // vendor store cannot carry the flag), but the topic record persisted the
        // connect-time proof, so strict restore must re-trust and re-activate it
        // rather than dropping the wallet on cold launch.
        let topic = WalletSessionTopicRecord(
            address: "0x0000000000000000000000000000000000000000",
            topic: "topic-1",
            chain: .ethereum,
            verified: true
        )
        let topicStore = InMemoryWalletSessionTopicStore(records: [topic])
        let activeStore = InMemoryActiveWalletStore()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: [.sampleSession]),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        let result = try await service.restoreSavedSessions()

        #expect(result.unverifiedSessionTopics.isEmpty)
        #expect(result.persistedAddresses.map(\.account.address) == ["0x0000000000000000000000000000000000000000"])
        #expect(activeStore.get() == "0x0000000000000000000000000000000000000000")
        #expect(await accountStore.upserted().map(\.account.address) == ["0x0000000000000000000000000000000000000000"])
    }

    @Test("Lifecycle persists the connect-time ownership proof onto the topic record")
    func lifecyclePersistsOwnershipProofOntoTopicRecord() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        // A session already flagged verified satisfies the strict policy without a
        // recovery-capable connector; persistence must record the proof so a later
        // restore can merge it back.
        let verifiedSession = WalletConnectorSession(
            id: "topic-1",
            topic: "topic-1",
            providerID: "generic",
            providerName: "Generic Wallet",
            accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000")],
            namespaces: [],
            expiryDate: .sampleDate,
            addressVerified: true
        )
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate }
        )

        _ = try await service.persistApprovedSession(verifiedSession)

        let records = await topicStore.loadAll()
        let allVerified = records.allSatisfy { $0.verified }
        #expect(records.isEmpty == false)
        #expect(allVerified)
    }

    @Test("Lifecycle restore failure does not delete topics deactivate accounts or clear active wallet")
    func lifecycleRestoreFailureDoesNotCleanupState() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-1"),
        ])
        let activeStore = InMemoryActiveWalletStore(address: "0x0000000000000000000000000000000000000000")
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(
                sessions: [],
                sessionsError: WalletConnectSessionStateStoreError.unreadable(errSecInteractionNotAllowed)
            ),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        await #expect(throws: WalletConnectSessionStateStoreError.self) {
            _ = try await service.restoreSavedSessions()
        }

        #expect(try await topicStore.load(walletAddress: "0x0000000000000000000000000000000000000000") == "topic-1")
        #expect(await accountStore.deactivated().isEmpty)
        #expect(activeStore.get() == "0x0000000000000000000000000000000000000000")
    }

    @Test("Lifecycle service deactivates stale Solana-only saved topics as Solana")
    func lifecycleDeactivatesStaleSolanaOnlySavedTopicsAsSolana() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: "11111111111111111111111111111111", topic: "expired-solana-topic"),
        ])
        let activeStore = InMemoryActiveWalletStore()
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        let result = try await service.restoreSavedSessions()

        #expect(result.persistedAddresses.isEmpty)
        #expect(result.removedSessionTopics == [
            WalletSessionTopicRecord(address: "11111111111111111111111111111111", topic: "expired-solana-topic"),
        ])
        let deactivated = await accountStore.deactivated()
        #expect(deactivated.map(\.address) == ["11111111111111111111111111111111"])
        #expect(deactivated.map(\.chain) == [.solana])
    }

    @Test("Lifecycle persists the account chain so stale non-mainnet EVM topics deactivate on the correct chain")
    func lifecyclePersistsChainForStaleNonMainnetEVMTopics() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        let baseSession = WalletConnectorSession(
            id: "topic-base",
            topic: "topic-base",
            providerID: "generic",
            providerName: "Generic Wallet",
            accounts: [WalletAccount(caip10: "eip155:8453:0x0000000000000000000000000000000000000000")],
            namespaces: [],
            expiryDate: .sampleDate
        )
        let persistService = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            ownershipPolicy: .allowUnverified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )
        _ = try await persistService.persistApprovedSession(baseSession)

        // No live sessions remain, so the saved topic is stale. It must be
        // deactivated on eip155:8453 (Base) — the persisted chain — not the
        // 0x-prefix fallback that would incorrectly assume Ethereum mainnet.
        let restoreService = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate.addingTimeInterval(-600) }
        )
        _ = try await restoreService.restoreSavedSessions()

        #expect(await accountStore.deactivated().map(\.chain) == [.base])
    }

    @Test("Lifecycle cleanup deactivates every stale same-address EVM chain")
    func lifecycleCleanupDeactivatesEveryStaleSameAddressEVMChain() async throws {
        let address = "0x0000000000000000000000000000000000000000"
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore()
        let activeStore = InMemoryActiveWalletStore()
        let multiChainSession = WalletConnectorSession(
            id: "topic-multichain",
            topic: "topic-multichain",
            providerID: "generic",
            providerName: "Generic Wallet",
            accounts: [
                WalletAccount(caip10: "eip155:1:\(address)"),
                WalletAccount(caip10: "eip155:8453:\(address)"),
            ],
            namespaces: [],
            expiryDate: .sampleDate
        )
        let persistService = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            ownershipPolicy: .allowUnverified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )
        _ = try await persistService.persistApprovedSession(multiChainSession)
        #expect(Set(await topicStore.loadAll()) == Set([
            WalletSessionTopicRecord(address: address, topic: "topic-multichain", chain: .ethereum),
            WalletSessionTopicRecord(address: address, topic: "topic-multichain", chain: .base),
        ]))

        let restoreService = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: []),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate.addingTimeInterval(-600) }
        )
        let result = try await restoreService.restoreSavedSessions()

        #expect(result.persistedAddresses.isEmpty)
        #expect(Set(result.removedSessionTopics) == Set([
            WalletSessionTopicRecord(address: address, topic: "topic-multichain", chain: .ethereum),
            WalletSessionTopicRecord(address: address, topic: "topic-multichain", chain: .base),
        ]))
        #expect(Set(await accountStore.deactivated().map(\.chain)) == Set([.ethereum, .base]))
        #expect(try await topicStore.loadAll().isEmpty)
    }

    @Test("Lifecycle restore preserves the previously-active wallet when it is still restored")
    func lifecycleRestorePreservesActiveWallet() async throws {
        let firstAddress = "0x0000000000000000000000000000000000000000"
        let lastAddress = "0x1111111111111111111111111111111111111111"
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        // Two live, verified sessions on distinct topics. The topic store enumerates
        // by account-key sort, so `firstAddress` (< `lastAddress`) restores first and
        // `lastAddress` restores last.
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: firstAddress, topic: "topic-1", chain: .ethereum),
            WalletSessionTopicRecord(address: lastAddress, topic: "topic-2", chain: .ethereum),
        ])
        // The user had `firstAddress` active — NOT the address that sorts last.
        let activeStore = InMemoryActiveWalletStore(address: firstAddress)
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: [
                WalletConnectorSession(
                    id: "topic-1",
                    topic: "topic-1",
                    providerID: "generic",
                    providerName: "Generic Wallet",
                    accounts: [WalletAccount(caip10: "eip155:1:\(firstAddress)")],
                    namespaces: [],
                    expiryDate: .sampleDate
                ),
                WalletConnectorSession(
                    id: "topic-2",
                    topic: "topic-2",
                    providerID: "generic",
                    providerName: "Generic Wallet",
                    accounts: [WalletAccount(caip10: "eip155:1:\(lastAddress)")],
                    namespaces: [],
                    expiryDate: .sampleDate
                ),
            ]),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            ownershipPolicy: .allowUnverified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        let result = try await service.restoreSavedSessions()

        // The user's active selection survives the relaunch rather than being
        // clobbered with the address that happened to sort last.
        #expect(activeStore.get() == firstAddress)
        #expect(result.activeAddress == firstAddress)
        #expect(Set(result.persistedAddresses.map(\.account.address)) == Set([firstAddress, lastAddress]))
    }

    @Test("Lifecycle restore falls back to the last restored wallet when the prior active is gone")
    func lifecycleRestoreFallsBackWhenActiveGone() async throws {
        let restoredAddress = "0x2222222222222222222222222222222222222222"
        let staleActive = "0x9999999999999999999999999999999999999999"
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: restoredAddress, topic: "topic-1", chain: .ethereum),
        ])
        // The previously-active wallet is no longer among the live/restored set.
        let activeStore = InMemoryActiveWalletStore(address: staleActive)
        let service = WalletConnectionLifecycleService(
            connector: FakeSessionWalletConnector(sessions: [
                WalletConnectorSession(
                    id: "topic-1",
                    topic: "topic-1",
                    providerID: "generic",
                    providerName: "Generic Wallet",
                    accounts: [WalletAccount(caip10: "eip155:1:\(restoredAddress)")],
                    namespaces: [],
                    expiryDate: .sampleDate
                ),
            ]),
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            ownershipPolicy: .allowUnverified,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        let result = try await service.restoreSavedSessions()

        #expect(activeStore.get() == restoredAddress)
        #expect(result.activeAddress == restoredAddress)
    }

    @Test("Lifecycle service removes wallet sessions and falls back active selection")
    func lifecycleRemovesWalletAndFallsBackActiveSelection() async throws {
        let accountStore = RecordingWalletAccountStore(fallbackAddress: "0x1111111111111111111111111111111111111111")
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: "0x0000000000000000000000000000000000000000", topic: "topic-1"),
        ])
        let activeStore = InMemoryActiveWalletStore(address: "0x0000000000000000000000000000000000000000")
        let cleaner = RecordingWalletRemovalCleaner()
        let connector = FakeSessionWalletConnector(sessions: [.sampleSession])
        let service = WalletConnectionLifecycleService(
            connector: connector,
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            removalCleaner: cleaner,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        try await service.remove(address: "0x0000000000000000000000000000000000000000", chain: .ethereum)

        #expect(await connector.disconnectedSessionIDs() == ["topic-1"])
        #expect(try await topicStore.load(walletAddress: "0x0000000000000000000000000000000000000000") == nil)
        #expect(await accountStore.deactivated().map(\.address) == ["0x0000000000000000000000000000000000000000"])
        #expect(await cleaner.cleanedAddresses() == ["0x0000000000000000000000000000000000000000"])
        #expect(activeStore.get() == "0x1111111111111111111111111111111111111111")
    }

    @Test("Lifecycle service removes wallets when the address case differs from the stored record")
    func lifecycleRemovesWalletWithDifferentAddressCase() async throws {
        let stored = "0xAbCdEf0000000000000000000000000000000001"
        let accountStore = RecordingWalletAccountStore(fallbackAddress: nil)
        let topicStore = InMemoryWalletSessionTopicStore(records: [
            WalletSessionTopicRecord(address: stored, topic: "topic-1", chain: .ethereum),
        ])
        let activeStore = InMemoryActiveWalletStore(address: stored)
        let connector = FakeSessionWalletConnector(sessions: [])
        let service = WalletConnectionLifecycleService(
            connector: connector,
            accountStore: accountStore,
            topicStore: topicStore,
            activeWalletStore: activeStore,
            now: { .sampleDate.addingTimeInterval(-600) }
        )

        // Caller passes a lowercased variant of a checksummed stored address.
        try await service.remove(address: stored.lowercased(), chain: .ethereum)

        #expect(await connector.disconnectedSessionIDs() == ["topic-1"])
        #expect(try await topicStore.loadAll().isEmpty)
        #expect(activeStore.get() == nil)
    }
}

@Suite("Wallet crypto provider")
struct WalletCryptoProviderTests {
    // Original Keccak-256 (Ethereum, 0x01 padding) known-answer vectors — NOT
    // FIPS-202 SHA3-256 (which uses 0x06 padding and yields different digests).
    // "" and "abc" are single sponge-block inputs; the fox sentences bracket the
    // 44-byte boundary; and the 341-byte MD5-description string crosses the
    // 136-byte rate to exercise the multi-block absorption loop in
    // `EthereumKeccak256.hash`. Vectors from the emn178/js-sha3 reference suite
    // (github.com/emn178/js-sha3/blob/master/tests/test.js, accessed 2026-08-05).
    @Test("Keccak-256 matches known Ethereum vectors", arguments: [
        (Data(), "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
        (Data("abc".utf8), "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"),
        (Data("The quick brown fox jumps over the lazy dog".utf8), "4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15"),
        (Data("The quick brown fox jumps over the lazy dog.".utf8), "578951e24efd62a3d63a86f7cd19aaa53c898fe287d2552133220370240b572d"),
        (Data("The MD5 message-digest algorithm is a widely used cryptographic hash function producing a 128-bit (16-byte) hash value, typically expressed in text format as a 32 digit hexadecimal number. MD5 has been utilized in a wide variety of cryptographic applications, and is also commonly used to verify data integrity.".utf8), "af20018353ffb50d507f1555580f5272eca7fdab4f8295db4b1a9ad832c93f6d"),
    ])
    func keccakMatchesKnownVectors(input: Data, expectedHex: String) {
        let digest = DefaultWalletConnectorCryptoProvider().keccak256(input)
        #expect(digest.hexString == expectedHex)
    }

    @Test("Default public key recovery fails with actionable error")
    func defaultPublicKeyRecoveryFailsWithActionableError() throws {
        let signature = WalletEthereumSignature(v: 27, r: Array(repeating: 1, count: 32), s: Array(repeating: 2, count: 32))

        do {
            _ = try DefaultWalletConnectorCryptoProvider().recoverPublicKey(signature: signature, message: Data("message".utf8))
            Issue.record("Expected public key recovery to throw")
        } catch let error as WalletConnectionError {
            #expect(error.errorDescription?.contains("Ethereum public key recovery is not configured") == true)
        }
    }
}

private actor RecordingWalletOpener: WalletApplicationOpening {
    private let canOpen: Bool
    private let openResult: Bool
    private var opened: [URL] = []

    init(canOpen: Bool, openResult: Bool) {
        self.canOpen = canOpen
        self.openResult = openResult
    }

    func canOpenURL(_ url: URL) -> Bool {
        canOpen
    }

    func open(_ url: URL) -> Bool {
        opened.append(url)
        return openResult
    }

    func openedURLs() -> [URL] {
        opened
    }
}

private actor RecordingReownAppKitClient: ReownAppKitClient {
    private let responseResult: String
    private var connectedWalletIDs: [String] = []
    private var callbackURLs: [URL] = []
    private var disconnectedIDs: [WalletSessionID] = []
    private var requestSessionIDs: [WalletSessionID] = []
    private var requests: [WalletRequest] = []

    init(responseResult: String = "approved") {
        self.responseResult = responseResult
    }

    nonisolated var events: AsyncStream<WalletConnectorEvent> {
        AsyncStream { $0.finish() }
    }

    func connect(proposalRequest: WalletSessionProposalRequest, wallet: ThirdPartyWalletProvider?) throws -> WalletConnectionStart {
        connectedWalletIDs.append(wallet?.id.rawValue ?? "generic-wallet")
        return WalletConnectionStart(
            pairingURI: WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000),
            qrPayload: "wc:topic-1@2"
        )
    }

    func connect(proposal: WalletNamespaceProposalSet, wallet: ThirdPartyWalletProvider?) throws -> WalletConnectionStart {
        try connect(proposalRequest: WalletSessionProposalRequest(requiredNamespaces: proposal), wallet: wallet)
    }

    func handleCallback(url: URL) {
        callbackURLs.append(url)
    }

    func sessions() -> [WalletConnectorSession] {
        [.sampleSession]
    }

    func disconnect(sessionId: WalletSessionID) {
        disconnectedIDs.append(sessionId)
    }

    func request(_ request: WalletRequest, in sessionId: WalletSessionID) -> WalletResponse {
        requestSessionIDs.append(sessionId)
        requests.append(request)
        return WalletResponse(id: request.id, result: responseResult)
    }

    func connectWalletIDs() -> [String] {
        connectedWalletIDs
    }

    func handledCallbackURLs() -> [URL] {
        callbackURLs
    }

    func disconnectedSessionIDs() -> [WalletSessionID] {
        disconnectedIDs
    }

    func requestedSessionIDs() -> [WalletSessionID] {
        requestSessionIDs
    }

    func requestedRequests() -> [WalletRequest] {
        requests
    }
}

private actor RecordingCoinbaseWalletSDKClient: CoinbaseWalletSDKClient {
    private let responseResult: String
    private var requestSessionIDs: [WalletSessionID] = []
    private var requests: [WalletRequest] = []

    init(responseResult: String = "approved") {
        self.responseResult = responseResult
    }

    nonisolated var events: AsyncStream<WalletConnectorEvent> {
        AsyncStream { $0.finish() }
    }

    func connect(wallet: ThirdPartyWalletProvider?) -> WalletConnectorSession {
        .sampleSession
    }

    func request(_ request: WalletRequest, in sessionId: WalletSessionID) -> WalletResponse {
        requestSessionIDs.append(sessionId)
        requests.append(request)
        return WalletResponse(id: request.id, result: responseResult)
    }

    func disconnect(sessionId: WalletSessionID) {}
    func handleCallback(url: URL) {}
    func sessions() -> [WalletConnectorSession] { [.sampleSession] }

    func requestedRequests() -> [WalletRequest] {
        requests
    }
}

private struct FixedRecoveryCryptoProvider: WalletConnectorCryptoProvider {
    let publicKey: Data

    var supportsRecovery: Bool { true }

    func recoverPublicKey(signature: WalletEthereumSignature, message: Data) throws -> Data {
        publicKey
    }

    func keccak256(_ data: Data) -> Data {
        EthereumKeccak256.hash(data)
    }
}

#if os(iOS)
private struct FakeReownCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        Data()
    }

    func keccak256(_ data: Data) -> Data {
        Data(repeating: 0, count: 32)
    }
}
#endif

private actor FakeWalletTransport: WalletTransportClient {
    private var requests: [WalletPairingRequest] = []

    func createPairing(request: WalletPairingRequest) throws -> WalletPairing {
        requests.append(request)
        // A real transport emits a canonical WalletConnect v2 URI (64-hex topic
        // + 64-hex symKey); the connector now gates on that shape, so the fixture
        // must too.
        let topic = String(repeating: "a", count: 64)
        let uri = WalletConnectURI(topic: topic, symKey: String(repeating: "b", count: 64), expiryTimestamp: 1_800_000_000)
        return WalletPairing(
            topic: WalletPairingTopic(rawValue: topic),
            providerID: request.providerID,
            uri: uri.absoluteString,
            expiryDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func disconnect(topic: WalletPairingTopic) throws {}
    func request(_ request: WalletRequest, topic: WalletPairingTopic) throws -> WalletResponse {
        WalletResponse(id: request.id, result: "")
    }
    func sessions() throws -> [WalletSession] { [] }
    nonisolated func events() -> AsyncStream<WalletTransportEvent> { AsyncStream { $0.finish() } }

    func pairingRequests() -> [WalletPairingRequest] {
        requests
    }
}

private actor RecordingRelayTask: WalletConnectRelayTask {
    private var sent: [String] = []
    private var receiveMessages: [String]
    private let receiveGates: [Int]
    private var receiveIndex = 0
    private var pendingReceives: [CheckedContinuation<String, Error>] = []
    private var isClosed = false

    init(receiveMessages: [String] = [], receiveGates: [Int]? = nil) {
        self.receiveMessages = receiveMessages
        self.receiveGates = receiveGates ?? Array(repeating: 0, count: receiveMessages.count)
    }

    func send(_ string: String) {
        sent.append(string)
        fulfillReceives()
    }

    func receive() async throws -> String {
        if isClosed {
            throw WalletConnectionError.relayDisconnected
        }
        if canDeliverNextMessage {
            return deliverNextMessage()
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingReceives.append(continuation)
        }
    }

    func close() {
        isClosed = true
        let continuations = pendingReceives
        pendingReceives.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: WalletConnectionError.relayDisconnected)
        }
    }

    func sentMessages() -> [String] {
        sent
    }

    func waitForSentCount(_ count: Int) async throws -> [String] {
        while sent.count < count {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        return sent
    }

    private var canDeliverNextMessage: Bool {
        guard !receiveMessages.isEmpty else { return false }
        let gate = receiveIndex < receiveGates.count ? receiveGates[receiveIndex] : 0
        return sent.count >= gate
    }

    private func deliverNextMessage() -> String {
        let messageIndex = receiveIndex
        receiveIndex += 1
        let message = receiveMessages.removeFirst()
        let gate = messageIndex < receiveGates.count ? receiveGates[messageIndex] : 0
        guard gate > 0, sent.indices.contains(gate - 1) else { return message }
        return message.replacingRelayAcknowledgementID(withRequestIDFrom: sent[gate - 1])
    }

    private func fulfillReceives() {
        while canDeliverNextMessage, !pendingReceives.isEmpty {
            let continuation = pendingReceives.removeFirst()
            continuation.resume(returning: deliverNextMessage())
        }
    }
}

private extension String {
    func replacingRelayAcknowledgementID(withRequestIDFrom request: String) -> String {
        guard
            let data = data(using: .utf8),
            var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["method"] == nil,
            json["result"] != nil || json["error"] != nil,
            let requestData = request.data(using: .utf8),
            let requestJSON = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
            let requestID = requestJSON["id"]
        else { return self }

        json["id"] = requestID
        guard
            let rewrittenData = try? JSONSerialization.data(withJSONObject: json),
            let rewritten = String(data: rewrittenData, encoding: .utf8)
        else { return self }
        return rewritten
    }
}

private struct FixedRelayTaskFactory: WalletConnectRelayTaskFactory {
    let task: RecordingRelayTask

    func makeTask(url: URL) async throws -> any WalletConnectRelayTask {
        task
    }
}

private actor FakeSessionWalletConnector: WalletConnector {
    private let storedSessions: [WalletConnectorSession]
    private let sessionsError: Error?
    private let verifiesOwnership: Bool
    private var disconnected: [WalletSessionID] = []
    private var ownershipChecks: [(address: String, chain: WalletChain, sessionId: WalletSessionID)] = []

    init(sessions: [WalletConnectorSession], sessionsError: Error? = nil, verifiesOwnership: Bool = false) {
        self.storedSessions = sessions
        self.sessionsError = sessionsError
        self.verifiesOwnership = verifiesOwnership
    }

    nonisolated var events: AsyncStream<WalletConnectorEvent> {
        AsyncStream { $0.finish() }
    }

    func connect(proposal: WalletNamespaceProposalSet, wallet: ThirdPartyWalletProvider?) throws -> WalletConnectionStart {
        WalletConnectionStart(
            pairingURI: WalletConnectURI(topic: "topic-1", symKey: "abc123", expiryTimestamp: 1_800_000_000),
            qrPayload: "wc:topic-1@2"
        )
    }

    func handleCallback(url: URL) {}

    func sessions() throws -> [WalletConnectorSession] {
        if let sessionsError { throw sessionsError }
        return storedSessions
    }

    func disconnect(sessionId: WalletSessionID) {
        disconnected.append(sessionId)
    }

    func request(_ request: WalletRequest, in sessionId: WalletSessionID) throws -> WalletResponse {
        throw WalletConnectionError.requestTimedOut(request.id)
    }

    func verifyOwnership(
        of address: String,
        chain: WalletChain,
        in sessionId: WalletSessionID,
        statement: String,
        expiryDate: Date
    ) throws -> Bool {
        ownershipChecks.append((address, chain, sessionId))
        return verifiesOwnership
    }

    func disconnectedSessionIDs() -> [WalletSessionID] {
        disconnected
    }

    func ownershipCheckAddresses() -> [String] {
        ownershipChecks.map(\.address)
    }
}

private actor RecordingWalletAccountStore: WalletAccountPersisting {
    private let fallbackAddress: String?
    private var upsertedAddresses: [WalletSessionAddress] = []
    private var deactivatedAddresses: [(address: String, chain: WalletChain)] = []

    init(fallbackAddress: String? = nil) {
        self.fallbackAddress = fallbackAddress
    }

    func upsert(_ walletAddress: WalletSessionAddress, selectedAt: Date) {
        upsertedAddresses.append(walletAddress)
    }

    func deactivate(address: String, chain: WalletChain, at date: Date) {
        deactivatedAddresses.append((address, chain))
    }

    func mostRecentlyUsedActiveAddress(excluding address: String?) -> String? {
        fallbackAddress
    }

    func upserted() -> [WalletSessionAddress] {
        upsertedAddresses
    }

    func deactivated() -> [(address: String, chain: WalletChain)] {
        deactivatedAddresses
    }
}

private actor RecordingWalletMetadataResolver: WalletPostConnectionResolving {
    private var addresses: [WalletSessionAddress] = []

    func refreshMetadata(for walletAddress: WalletSessionAddress) {
        addresses.append(walletAddress)
    }

    func refreshed() -> [WalletSessionAddress] {
        addresses
    }
}

private actor RecordingWalletRemovalCleaner: WalletRemovalCleaning {
    private var addresses: [String] = []

    func cleanLocalData(for address: String) {
        addresses.append(address)
    }

    func cleanedAddresses() -> [String] {
        addresses
    }
}

private let realKeychainSessionTopicStoreIsAvailable: Bool = {
    let service = uniqueKeychainService()
    let factory = KeychainSessionTopicQueryFactory(service: service)
    var query = factory.addQuery(
        walletAddress: "availability-check",
        topicData: Data("topic".utf8),
        chain: .ethereum
    )
    query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    _ = SecItemDelete(factory.allItemsQuery() as CFDictionary)
    return status == errSecSuccess
}()

private func uniqueKeychainService() -> String {
    "com.auraplay.walletconnect.tests.\(UUID().uuidString)"
}

private func deleteAllKeychainTopicRecords(service: String) throws {
    let status = SecItemDelete(KeychainSessionTopicQueryFactory(service: service).allItemsQuery() as CFDictionary)
    switch status {
    case errSecSuccess, errSecItemNotFound:
        return
    default:
        throw WalletSessionTopicStoreError.keychainFailure(status)
    }
}

private func keychainTopicAttributes(service: String, walletAddress: String, chain: WalletChain?) throws -> [String: Any]? {
    let factory = KeychainSessionTopicQueryFactory(service: service)
    var query = factory.lookupQuery(walletAddress: walletAddress, chain: chain)
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
        return result as? [String: Any]
    case errSecItemNotFound:
        return nil
    default:
        throw WalletSessionTopicStoreError.keychainFailure(status)
    }
}

private func keychainSessionStateBaseQuery(service: String) -> [String: Any] {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: WalletKeychainRecordKind.sessionRecord.rawValue,
        kSecAttrSynchronizable as String: false,
    ]
#if os(macOS)
    query[kSecUseDataProtectionKeychain as String] = true
#endif
    return query
}

private func deleteKeychainSessionStateRecord(service: String) throws {
    let status = SecItemDelete(keychainSessionStateBaseQuery(service: service) as CFDictionary)
    switch status {
    case errSecSuccess, errSecItemNotFound:
        return
    default:
        throw WalletConnectSessionStateStoreError.writeFailed(status)
    }
}

private func keychainSessionStateAttributes(service: String) throws -> [String: Any]? {
    var query = keychainSessionStateBaseQuery(service: service)
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
        return result as? [String: Any]
    case errSecItemNotFound:
        return nil
    default:
        throw WalletConnectSessionStateStoreError.unreadable(status)
    }
}

private func assertRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
    let data = try JSONEncoder.walletConnectorTest.encode(value)
    let decoded = try JSONDecoder.walletConnectorTest.decode(Value.self, from: data)
    #expect(decoded == value)
}

private extension JSONEncoder {
    static var walletConnectorTest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var walletConnectorTest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Date {
    static let sampleDate = Date(timeIntervalSince1970: TimeInterval(Int(Date().addingTimeInterval(3_600).timeIntervalSince1970)))
}

private extension WalletConnectorSession {
    static let sampleSession = WalletConnectorSession(
        id: "topic-1",
        topic: "topic-1",
        providerID: "metamask",
        providerName: "MetaMask",
        accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000")],
        namespaces: [
            WalletSessionNamespace(
                name: "eip155",
                accounts: [WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000")],
                methods: ["personal_sign"],
                events: ["accountsChanged"]
            ),
        ],
        expiryDate: .sampleDate
    )

    static let multiAccountSession = WalletConnectorSession(
        id: "topic-1",
        topic: "topic-1",
        providerID: "generic",
        providerName: "Generic Wallet",
        accounts: [
            WalletAccount(caip10: "eip155:1:0x0000000000000000000000000000000000000000"),
            WalletAccount(caip10: "solana:mainnet:11111111111111111111111111111111"),
        ],
        namespaces: [],
        expiryDate: .sampleDate
    )
}

private extension WalletConnectionMetadata {
    static let testValue = WalletConnectionMetadata(
        appName: "Auralis",
        appDescription: "Auralis wallet connection",
        appURL: URL(string: "https://auralis.example")!,
        redirect: WalletConnectionRedirect(native: "auralis-wcdemo://")
    )
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
