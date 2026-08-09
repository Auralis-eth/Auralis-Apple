import Foundation

public final class WalletConnectDAppConnector: WalletConnector, @unchecked Sendable {
    public let runtimeFamily: WalletConnectorRuntimeFamily = .customWalletConnectIRN
    private let transport: any WalletTransportClient
    private let launcher: DeepLinkWalletLauncher?
    private let metadata: WalletConnectionMetadata
    public let readiness: WalletConnectorReadiness
    private let callbackURL: URL?
    private let returnURLHandler: WalletReturnURLHandler
    private let cryptoProvider: (any WalletConnectorCryptoProvider)?
    private let eventsStream: AsyncStream<WalletConnectorEvent>
    private let eventsContinuation: AsyncStream<WalletConnectorEvent>.Continuation
    // Bridges transport events onto this connector's event stream. Retained so it
    // can be cancelled in `deinit`; `transport.events()` never finishes on its own
    // while this connector holds the transport, so without an explicit cancel the
    // task would run forever and pin the transport (and its relay + WebSocket)
    // alive. Assigned exactly once in `init` (before concurrency touches it) and
    // read only in `deinit`, so `nonisolated(unsafe)`-equivalent access is sound
    // for this `@unchecked Sendable` class.
    private var eventBridgeTask: Task<Void, Never>?

    public init(
        transport: any WalletTransportClient,
        launcher: DeepLinkWalletLauncher? = nil,
        metadata: WalletConnectionMetadata,
        callbackURL: URL? = nil,
        returnURLHandler: WalletReturnURLHandler? = nil,
        cryptoProvider: (any WalletConnectorCryptoProvider)? = nil,
        readiness: WalletConnectorReadiness? = nil
    ) {
        self.transport = transport
        self.launcher = launcher
        self.metadata = metadata
        self.callbackURL = callbackURL
        self.cryptoProvider = cryptoProvider
        self.readiness = readiness ?? Self.defaultReadiness(cryptoProvider: cryptoProvider)
        // Scope the inbound-callback handler to this app's own redirect scheme
        // and callback host by default, so a crafted deep link from another
        // origin cannot inject a Link Mode envelope. Callers can still pass an
        // explicit handler (including a deliberately permissive one).
        self.returnURLHandler = returnURLHandler ?? Self.scopedReturnURLHandler(metadata: metadata, callbackURL: callbackURL)
        let stream = AsyncStream<WalletConnectorEvent>.makeStream()
        self.eventsStream = stream.stream
        self.eventsContinuation = stream.continuation
        bridgeTransportEvents()
    }

    deinit {
        // Stop the bridge loop so it releases the transport, letting the transport
        // (and its relay actor + live socket) deallocate instead of leaking behind
        // an endless `transport.events()` iteration.
        eventBridgeTask?.cancel()
    }

    public var events: AsyncStream<WalletConnectorEvent> {
        eventsStream
    }

    private static func defaultReadiness(cryptoProvider: (any WalletConnectorCryptoProvider)?) -> WalletConnectorReadiness {
        guard cryptoProvider?.supportsRecovery == true else {
            return .experimental("Custom IRN transport is configured, but no recovery-capable WalletConnectorCryptoProvider was injected; EVM ownership verification fails closed. Inject a secp256k1 recovery provider for production EVM identity flows.")
        }
        return .productionReady
    }

    public func connect(
        proposalRequest: WalletSessionProposalRequest = .defaultV1Optional,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart {
        let provider = wallet ?? WalletConnectorCatalog.genericWallet
        let preferredChain = proposalRequest.mergedProposalSet.proposals.values
            .flatMap(\.chains)
            .compactMap(\.knownChain)
            .first

        let pairing = try await transport.createPairing(
            request: WalletPairingRequest(
                providerID: provider.id,
                preferredChain: preferredChain,
                supportedChains: provider.supportedChains,
                metadata: metadata,
                callbackURL: callbackURL,
                requiredNamespaces: proposalRequest.requiredNamespaces,
                optionalNamespaces: proposalRequest.optionalNamespaces
            )
        )
        // Gate on the canonical WalletConnect v2 shape (64-hex topic + 64-hex
        // symKey) before the URI can drive any pairing/key derivation, so a
        // transport that returned a truncated/malformed key never reaches the
        // crypto layer. This is the enforcement the security notes describe.
        guard let pairingString = pairing.uri,
              let uri = WalletConnectURI(absoluteString: pairingString),
              uri.isCanonicalV2 else {
            throw WalletConnectionError.invalidPairingURI
        }

        var openURL: URL?
        if let launcher, wallet != nil {
            try await launcher.launch(provider: provider, pairingURI: uri, redirect: metadata.redirect)
            if let scheme = provider.deepLinkScheme {
                openURL = WalletProviderDeepLink(providerID: provider.id, scheme: scheme).url(pairingURI: uri, redirect: metadata.redirect)
            }
        }

        eventsContinuation.yield(.pairingCreated(uri))
        return WalletConnectionStart(pairingURI: uri, walletOpenURL: openURL, qrPayload: uri.absoluteString)
    }

    public func connect(
        proposal: WalletNamespaceProposalSet = .defaultV1,
        wallet: ThirdPartyWalletProvider?
    ) async throws -> WalletConnectionStart {
        try await connect(
            proposalRequest: WalletSessionProposalRequest(requiredNamespaces: .empty, optionalNamespaces: proposal),
            wallet: wallet
        )
    }

    /// Classifies an inbound wallet-return URL.
    ///
    /// The IRN relay transport receives every protocol message (settle, request
    /// responses, deletes) over its WebSocket, so a foreground-return callback is
    /// a no-op here — it only exists to bring the app forward. A Link Mode
    /// (`wc_ev`) envelope, however, carries protocol payload *out of band* and
    /// this relay transport cannot route it (there is no topic to bind it to), so
    /// rather than silently dropping it — which looks like success — we surface it
    /// as explicitly unsupported. Out-of-scope URLs are rejected by the scoped
    /// `returnURLHandler` and classified as `nil` (ignored).
    public func handleCallback(url: URL) async throws {
        switch returnURLHandler.handle(url) {
        case .none, .foreground?:
            return
        case .linkModeEnvelope?:
            throw WalletConnectionError.unavailable(
                "Link Mode (wc_ev) callbacks are not supported by the IRN relay transport. Use a WalletConnect SDK-backed connector for Link Mode, or deliver session traffic over the relay."
            )
        }
    }

    /// Builds a return-URL handler scoped to the app's own redirect scheme and
    /// callback host (plus the `wc` foreground marker). Falls back to an
    /// unscoped handler only when no scheme can be derived.
    private static func scopedReturnURLHandler(metadata: WalletConnectionMetadata, callbackURL: URL?) -> WalletReturnURLHandler {
        var schemes = Set<String>()
        var hosts: Set<String> = ["wc"]
        if let native = metadata.redirect?.native, let url = URL(string: native) {
            if let scheme = url.scheme { schemes.insert(scheme) }
            if let host = url.host { hosts.insert(host) }
        }
        if let callbackURL {
            if let scheme = callbackURL.scheme { schemes.insert(scheme) }
            if let host = callbackURL.host { hosts.insert(host) }
        }
        guard !schemes.isEmpty else {
            return WalletReturnURLHandler()
        }
        return WalletReturnURLHandler(allowedSchemes: schemes, allowedHosts: hosts)
    }

    public func sessions() async throws -> [WalletConnectorSession] {
        try await transport.sessions().map(\.connectorSession)
    }

    public func disconnect(sessionId: WalletSessionID) async throws {
        try await transport.disconnect(topic: WalletPairingTopic(rawValue: sessionId.rawValue))
        eventsContinuation.yield(.sessionDeleted(sessionId))
    }

    public func request(_ request: WalletRequest, in sessionId: WalletSessionID) async throws -> WalletResponse {
        try WalletRequestValidation.validate(request)
        return try await transport.request(request, topic: WalletPairingTopic(rawValue: sessionId.rawValue))
    }

    /// Proves the connected wallet actually controls `address` by issuing an
    /// EIP-4361 (Sign-In with Ethereum) `personal_sign` challenge and verifying
    /// the returned signature recovers `address`.
    ///
    /// Settling a session only proves the wallet *claims* an address; nothing in
    /// the handshake proves key control. Call this after connecting (and before
    /// trusting the address for anything sensitive). It **fails closed**: if no
    /// `cryptoProvider` capable of secp256k1 recovery was injected, it throws
    /// `WalletConnectionError.unavailable` rather than silently reporting success.
    ///
    /// The signed message is a SIWE-shaped `personal_sign` ownership challenge (not
    /// a fully EIP-4361-conformant SIWE payload — the address is not EIP-55
    /// checksummed and the ABNF is not guaranteed, which is fine because this app
    /// both mints and verifies it over the exact bytes rather than handing it to a
    /// SIWE-authenticating backend). It binds the app domain, URI, chain id, a
    /// high-entropy nonce, and an issued-at/expiration window so a captured
    /// signature cannot be replayed against another domain or after it expires. The
    /// full message text is what the wallet signs and what we recover against.
    ///
    /// - Returns: `true` when the signature recovers `address`.
    @discardableResult
    public func verifyOwnership(
        of address: String,
        chain: WalletChain = .ethereum,
        in sessionId: WalletSessionID,
        statement: String = "Verify wallet ownership.",
        expiryDate: Date = Date().addingTimeInterval(300)
    ) async throws -> Bool {
        let verified: Bool
        switch chain.namespace {
        case "eip155":
            verified = try await verifyEVMOwnership(of: address, chain: chain, in: sessionId, statement: statement, expiryDate: expiryDate)
        case "solana":
            verified = try await verifySolanaOwnership(of: address, chain: chain, in: sessionId, statement: statement, expiryDate: expiryDate)
        default:
            throw WalletConnectionError.unsupportedChain(chain)
        }
        // Record proven ownership on the session so `sessions()` (and a
        // cross-launch restore) reports `addressVerified == true` instead of the
        // caller having to remember this out-of-band.
        //
        // Persisting the flag is **best-effort**: ownership has already been
        // cryptographically proven at this point, so a transient keychain hiccup
        // (device locked, momentary unavailability) must not turn a genuine proof
        // into a thrown error. The worst case is that the flag is not persisted and
        // the wallet re-verifies on the next launch — a re-prompt, not a security
        // regression. The persisted-state failure still surfaces on the transport's
        // own event stream (`.sessionRejected` with the persistence error).
        if verified {
            try? await transport.markOwnershipVerified(topic: WalletPairingTopic(rawValue: sessionId.rawValue))
        }
        return verified
    }

    /// EVM ownership via an EIP-4361 (SIWE) `personal_sign` challenge + secp256k1
    /// recovery. Requires an injected recovery-capable crypto provider; fails
    /// closed (throws) if none was supplied rather than reporting a false success.
    private func verifyEVMOwnership(
        of address: String,
        chain: WalletChain,
        in sessionId: WalletSessionID,
        statement: String,
        expiryDate: Date
    ) async throws -> Bool {
        guard let cryptoProvider else {
            throw WalletConnectionError.unavailable(
                "EVM ownership verification requires a WalletConnectorCryptoProvider with secp256k1 recovery. Inject one via WalletConnectDAppConnector(cryptoProvider:)."
            )
        }

        // High-entropy nonce so a captured signature cannot be replayed.
        let nonce = try WalletOwnershipChallengeMessageBuilder.nonce()
        let messageText = WalletOwnershipChallengeMessageBuilder.evmSIWEMessage(
            address: address,
            chain: chain,
            statement: statement,
            nonce: nonce,
            issuedAt: Date(),
            expiration: expiryDate,
            metadata: metadata
        )
        let requestID = WalletSignRequestID(rawValue: "ownership-\(nonce)")
        let challenge = WalletRequestBuilder.personalSignText(
            id: requestID,
            address: address,
            text: messageText,
            chain: chain,
            expiryDate: expiryDate
        )
        let response = try await request(challenge, in: sessionId)
        // Accepts an EOA signature (secp256k1 recovery) or, when the injected
        // provider supports it, an EIP-1271 smart-contract-wallet signature. A
        // contract wallet (Safe / Coinbase Smart Wallet / ERC-4337) has no
        // recoverable key, so EOA-only verification would reject it.
        return try await WalletOwnershipVerifier.verifyPersonalSign(
            expectedAddress: address,
            message: Data(messageText.utf8),
            signatureHex: response.result,
            chain: chain,
            using: cryptoProvider
        )
    }

    /// Solana ownership via an ed25519 `solana_signMessage` challenge. A Solana
    /// address *is* its ed25519 public key, so this is fully self-contained (no
    /// crypto provider needed). The challenge bytes are base58-encoded on the wire
    /// (the `solana_signMessage` convention); the wallet signs the decoded bytes,
    /// which is exactly what we verify against.
    private func verifySolanaOwnership(
        of address: String,
        chain: WalletChain,
        in sessionId: WalletSessionID,
        statement: String,
        expiryDate: Date
    ) async throws -> Bool {
        let nonce = try WalletOwnershipChallengeMessageBuilder.nonce()
        let messageText = WalletOwnershipChallengeMessageBuilder.solanaMessage(
            address: address,
            statement: statement,
            nonce: nonce,
            issuedAt: Date(),
            expiration: expiryDate,
            metadata: metadata
        )
        return try await WalletSolanaOwnershipVerifier.verifyChallenge(
            address: address,
            challengeText: messageText,
            expiryDate: expiryDate,
            send: { try await request($0, in: sessionId) }
        )
    }

    private func bridgeTransportEvents() {
        // Grab the stream value *before* the closure so the task captures the
        // `AsyncStream` (a value type retaining only its buffer, not the transport
        // object) plus a weak `self` — never `transport`. When this connector is
        // deallocated, `deinit` cancels the task and the `let transport` property
        // releases, so the transport can finish and deallocate.
        let stream = transport.events()
        eventBridgeTask = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                self.forward(event)
            }
        }
    }

    private func forward(_ event: WalletTransportEvent) {
        switch event {
        case .pairingCreated(let pairing):
            if let uri = pairing.uri.flatMap(WalletConnectURI.init(absoluteString:)) {
                eventsContinuation.yield(.pairingCreated(uri))
            }
        case .sessionApproved(let session):
            eventsContinuation.yield(.sessionSettled(session.connectorSession))
        case .sessionUpdated(let session):
            eventsContinuation.yield(.sessionUpdated(session.connectorSession))
        case .sessionEvent(let event):
            eventsContinuation.yield(.sessionEvent(event))
        case .sessionRejected(_, let error):
            eventsContinuation.yield(.sessionRejected(error))
        case .sessionDeleted(let sessionID):
            eventsContinuation.yield(.sessionDeleted(sessionID))
        case .pairingExpired:
            eventsContinuation.yield(.sessionRejected(.pairingExpired))
        case .requestExpired(let requestID):
            eventsContinuation.yield(.requestExpired(requestID))
        case .responseReceived(let response):
            eventsContinuation.yield(.responseReceived(response))
        case .peerAcknowledgementFailed(let failure):
            eventsContinuation.yield(.peerAcknowledgementFailed(failure))
        case .socketStatusChanged(let status):
            eventsContinuation.yield(.socketStatusChanged(status))
        }
    }
}

public extension WalletEthereumSignature {
    /// Parses a 65-byte `0x`-prefixed `r ‖ s ‖ v` hex signature (the EVM
    /// `eth_sign`/`personal_sign` return layout). `v` is normalized to 27/28 if
    /// the wallet returns the 0/1 recovery id. Returns `nil` for any other shape.
    init?(hexSignature: String) {
        var hex = hexSignature
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex.removeFirst(2) }
        guard hex.count == 130, let data = WalletConnectV2Crypto.data(hexEncoded: hex) else {
            return nil
        }
        let bytes = [UInt8](data)
        let r = Array(bytes[0..<32])
        let s = Array(bytes[32..<64])
        // `personal_sign`/`eth_sign` return the recovery id as either 0/1 or the
        // legacy 27/28. Normalize to 27/28 and reject anything else (fail closed)
        // instead of passing an out-of-range `v` through to recovery.
        let recovery: UInt8
        switch bytes[64] {
        case 0, 1:
            recovery = bytes[64]
        case 27, 28:
            recovery = bytes[64] - 27
        default:
            return nil
        }
        self.init(v: 27 + recovery, r: r, s: s)
    }
}
