# WalletConnectorKit

A Swift package for connecting the Auralis app to external and embedded crypto
wallets. The core `WalletConnectorKit` target is SDK-free (no Reown, wallet
SDKs, UIKit, or SwiftUI) and ships a self-contained WalletConnect v2 Sign
transport over the IRN relay. Wallet-specific integrations live in separate
adapter products (Reown, Coinbase, MetaMask, Privy, Dynamic, Solana).

## Products

| Product | Purpose |
| --- | --- |
| `WalletConnectorKit` | Core domain types, registry, custom WalletConnect v2 IRN transport, persistence. SDK-free. |
| `WalletConnectorKitReownAdapter` | Reown AppKit-backed connector. |
| `WalletConnectorKitCoinbaseAdapter` | Direct Coinbase Mobile Wallet Protocol connector. |
| `WalletConnectorKitMetaMaskAdapter` | Legacy MetaMask native SDK connector (deprecated upstream). |
| `WalletConnectorKitPrivyAdapter` / `WalletConnectorKitDynamicAdapter` | Embedded-wallet / auth providers. |
| `WalletConnectorKitSolanaAdapter` | Solana-only connector. |

## Configuration

### Relay project ID (custom IRN transport)

`WalletConnectRelayConfiguration` requires a WalletConnect/Reown **project ID**.
The relay rejects unauthenticated sockets, so a `WalletConnectRelayAuthProviding`
(default: `WalletConnectKeychainRelayAuthProvider`) attaches a signed Ed25519
DID-JWT alongside the project ID.

```swift
let relay = WalletConnectIRNRelayClient(
    configuration: WalletConnectRelayConfiguration(projectID: "<your-project-id>")
)
```

The default relay host is `wss://relay.walletconnect.org` (the legacy `.com`
host is deprecated).

### Reown adapter project ID

The Reown adapter reads `REOWN_PROJECT_ID`. Supply it through
`ReownAppKitConfiguration`; when it is missing the adapter throws
`WalletConnectionError.unavailable`.

### Cross-launch session restoration

When using the custom `WalletConnectIRNTransportClient`, inject a
`KeychainWalletConnectSessionStateStore` so sessions survive relaunch. The
default `InMemoryWalletConnectSessionStateStore` is for tests only.

```swift
let store = KeychainWalletConnectSessionStateStore(
    onPersistenceDegraded: { status in
        // Keychain unavailable — this session was NOT persisted. Surface/telemetry.
    }
)
let transport = WalletConnectIRNTransportClient(relayClient: relay, stateStore: store)
```

On settle the transport persists the session symmetric key, the local X25519
key-agreement key, the pairing lineage, and session metadata, then rehydrates
and re-subscribes on the next launch (pruning expired records). Persistence is
device-local, non-syncing, and readable only while unlocked. Persistence is
**best effort**: if the keychain is unavailable the write is dropped (and
`onPersistenceDegraded` fires) rather than hard-failing a live connection.

## Verifying wallet ownership (important)

Settling a session only proves a wallet **claims** an address — it does **not**
prove the user controls the private key. To establish ownership you must issue a
signing challenge and verify the signature. This requires secp256k1 public-key
recovery, which this package does not vend: inject a
`WalletConnectorCryptoProvider` (the Auralis app supplies one backed by
web3.swift).

```swift
let connector = WalletConnectDAppConnector(
    transport: transport,
    metadata: metadata,
    cryptoProvider: appCryptoProvider // secp256k1 recovery
)

// After connecting, before trusting the address:
let owns = try await connector.verifyOwnership(of: address, in: sessionID)
guard owns else { /* reject */ }
```

`verifyOwnership` **fails closed**: without a recovery-capable `cryptoProvider`
it throws instead of silently returning success. `DefaultWalletConnectorCryptoProvider`
does not implement recovery and will throw if used for verification.

### `personal_sign` message encoding

`WalletRequestBuilder.personalSign(message:)` places `message` on the wire
verbatim; per EIP-191 that parameter should be `0x`-hex. To sign human-readable
text, use `personalSignText(text:)`, which hex-encodes the UTF-8 bytes.

## Host app configuration checklist

- Register the native callback scheme used by wallet redirects.
- Add every wallet deep-link scheme to `LSApplicationQueriesSchemes`.
- Scope `WalletReturnURLHandler` to your app's callback scheme/hosts.
- Route SceneDelegate, SwiftUI `.onOpenURL`, and universal-link callbacks
  through one `WalletInboundURLCoordinator` (dedup + operation-ID correlation).

## Transport security notes

Relay payloads are end-to-end encrypted (X25519 + HKDF-SHA256, ChaCha20-Poly1305),
so the relay never sees plaintext. TLS certificate pinning on the relay socket is
**not** applied — it is defense-in-depth only given E2E encryption, and pinning a
third-party relay certificate is operationally fragile. Revisit if your threat
model requires it.

See `WalletConnectorKit-QA-Checklist.md` for the full verification matrix.
</content>
</invoke>
