# WalletConnectorKit QA Checklist

Use this checklist after the clean-room package work is wired into a host app.
The package remains SDK-free: no production source imports Reown, WalletConnect
SDK modules, UIKit, or SwiftUI.

## Package Contract

| Test | Expected result |
| --- | --- |
| Provider catalog | Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, Dynamic, and Generic Wallet are present. |
| Chain filtering | EVM providers appear for EVM chains; Solana-only providers do not appear for EVM chains. |
| CAIP parsing | Supported EVM and Solana CAIP-2 / CAIP-10 values parse and malformed values are rejected. |
| WalletConnect URI | `wc:` URI formatting and parsing round-trip with a single nested percent-encoding pass. |
| Deep-link launcher | Installed wallet path calls the injected opener; missing wallet maps to a typed package error. |
| Return URL handler | Foreground callbacks and future `wc_ev` envelopes are classified without invoking SDK code. |
| Session store | Save, load, list, and delete behavior works through `WalletSessionStore` with no network or Keychain dependency in default tests. |
| Session topic store | Session topics round-trip through `WalletSessionTopicStoring`; Keychain queries use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecAttrSynchronizable: false`. |
| Request builders | EVM and Solana signing requests create deterministic method, chain, params, and TTL values. |
| Lifecycle service | Approved sessions persist addresses and topics, launch restore keeps live sessions, expired saved topics are deleted, and removal falls back active wallet selection. |

## Host App Configuration

| Test | Expected result |
| --- | --- |
| Native callback scheme | The host app registers the callback scheme used in `WalletConnectionRedirect.native`. |
| Query schemes | `LSApplicationQueriesSchemes` includes every `.deepLink(scheme:)` value the host wants to probe with `canOpenURL`. |
| URL opening adapter | The app owns the `WalletApplicationOpening` implementation and wraps platform APIs outside the package. |
| QR fallback | If no wallet can be opened, the app shows the returned `WalletConnectionStart.qrPayload`. |

## Fake Integration

| Test | Expected result |
| --- | --- |
| Pairing creation | `WalletConnectDAppConnector.connect` asks the injected transport for a pairing and returns a QR payload. |
| Wallet open | Selected wallet deep link is opened only through `WalletApplicationOpening`. |
| Session settlement | Fake relay approval emits a settled `WalletConnectorSession`. |
| Rejection | Fake relay rejection emits a typed `WalletConnectionError`. |
| Disconnect | Disconnect calls the transport with the session topic and emits deletion. |
| Request timeout | Missing response emits `requestExpired` and throws `requestTimedOut`. |

## Manual Smoke

| Test | Expected result |
| --- | --- |
| Copy QR payload | A WalletConnect-compatible wallet can scan or copy the `wc:` payload. |
| Deep-link handoff | An installed wallet opens from `<scheme>://wc?uri=...`. |
| Return to app | The wallet can foreground the app via the registered callback scheme. |
| Offline relay | Transport disconnect state surfaces without crashing. |
| Relaunch | Persisted sessions reload through the package connector API once a concrete store is wired. |
| Removal | Removing the active wallet disconnects the topic, deactivates the wallet through the host adapter, cleans scoped local data, and selects the next active wallet or clears selection. |
