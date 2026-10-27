# WalletConnectorKit Project Memory

## Project Overview

WalletConnectorKit is the reusable wallet-connection package for Auralis. The core target defines wallet-domain types, request builders, lifecycle services, persistence contracts, and a custom WalletConnect v2 IRN transport. Provider-specific integrations live in adapter targets so the core target stays SDK-free.

## Architecture Decisions

- `WalletConnectorKit` is the SDK-free core. It must not import Reown, CoinbaseWalletSDK, UIKit, SwiftUI, or vendor SDKs.
- Adapter targets own vendor bridges: Reown AppKit, Coinbase Wallet SDK, and current stub adapters for MetaMask, Privy, Dynamic, and Solana.
- The custom IRN transport owns WalletConnect v2 relay auth, encrypted envelopes, session lifecycle handling, request validation, and lazy restoration through injected session-state storage.
- `WalletConnectionLifecycleService` coordinates approved sessions, restoration, ownership policy, and cleanup through injected collaborators instead of depending on app storage or UI frameworks.
- Reown App Group setup belongs to the signed host app target, not this package. The package may document the requirement and expose configuration, but the app/extension targets own `com.apple.security.application-groups` entitlements, provisioning, and concrete `group...` identifiers.

## Important Conventions

- Prefer Swift Concurrency and actor isolation for mutable connection/session state.
- Prefer typed wallet request payloads over JSON encoded as strings.
- Keep connector readiness honest. Stub or unconfigured SDK clients report `.unavailable`; only live configured clients should be routed for production use.
- Treat settled wallet addresses as claimed until `addressVerified == true`; sensitive flows should use `WalletConnectionLifecycleService(ownershipPolicy: .requireVerified)`.
- Preserve package boundaries. Host-specific bundle IDs, callback schemes, App Groups, provisioning profiles, and Info.plist entries should be documented here but configured in the host app.

## Build And Run

- Use the `WalletConnectorKit` package/scheme in Xcode.
- Build with Xcode or the MCP `BuildProject` tool.
- Run the package test suite with Swift Testing; UI tests do not belong in this package.

## Verification & QA Status

- The former append-only `AI-Audit-Log.md` has been retired. Its durable conclusions now live in `WalletConnectorKit-QA-Checklist.md`: the Manual Live-Wallet Suite (the standing on-device ship gate), the Known Limitations & Deliberate Non-Fixes table, and the Verification Status summary.
- The SDK-free core is production-grade by static/unit verification; the single outstanding ship gate for live wallets (Reown/Coinbase/Privy/Dynamic) is on-device QA, which cannot be closed by an automated session (no device or real wallet credentials available). Treat it as a hard gate before routing any live vendor client to production.

## Quirks And Gotchas

- `KeychainWalletConnectSessionStateStore` is production storage for the custom IRN transport; the in-memory store is test-only.
- Restoration is lazy. Call `sessions()` or `WalletConnectionLifecycleService.restoreSavedSessions()` during app launch so restored topics drain `irn_fetchMessages` and re-subscribe early; relay recovery failure must leave persisted user state untouched.
- Reown/AppKit is iOS-only in this package. Unsupported platforms should report unavailable rather than pretending the live SDK path exists.
- App Groups are code-signing capabilities. Do not add entitlement files or hard-coded App Group IDs to this reusable Swift package unless it grows an actual signed app or extension target.
