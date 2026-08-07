# WalletConnectorKit QA Checklist

Use this checklist after the SDK-backed package work is wired into a host app.
The core `WalletConnectorKit` target remains SDK-free, while adapter targets may import Reown and wallet-specific SDKs.

## Package Contract

| Test | Expected result |
| --- | --- |
| Core dependency boundary | `WalletConnectorKit` does not import Reown, wallet SDKs, UIKit, or SwiftUI. |
| Adapter products | Reown, Coinbase, MetaMask, Privy, Dynamic, and Solana adapter products are available as separate package products. |
| Provider catalog | Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, Dynamic, and Generic Wallet are present. |
| Chain and method filtering | EVM providers appear for EVM methods; Solana methods only return Solana-capable providers. |
| CAIP parsing | Supported EVM and Solana CAIP-2 / CAIP-10 values parse and malformed values are rejected. |
| WalletConnect URI | `wc:` URI formatting and parsing round-trip with a single nested percent-encoding pass. |
| QR presentation | Pairing presentation exposes provider, URI, QR payload, expiry, optional open URL, and connection state. |
| Request builders | Personal sign, typed-data sign, send transaction, switch chain, add chain, and Solana sign message produce deterministic payloads. |
| Error mapping | Rejection, timeout, missing wallet, unsupported method, unsupported chain, and disconnect messages map to typed package errors. |
| Lifecycle service | Approved sessions persist addresses and topics, launch restore keeps live sessions, expired saved topics are deleted, and removal falls back active wallet selection. |

## Reown Adapter

| Test | Expected result |
| --- | --- |
| AppKit availability | Reown adapter reports unavailable on unsupported platforms and works on iOS. |
| Connection start | Reown-backed connector creates a pairing or AppKit session start and emits pairing/approval state. |
| Session mapping | Reown/AppKit sessions map into `WalletConnectorSession` with topic, provider, accounts, namespaces, and expiry. |
| Callback handling | Host URL callbacks are forwarded through the Reown adapter and do not touch core target code. |
| Request bridge | `personal_sign`, typed-data signing, send transaction, switch chain, and add chain produce a response or typed rejection. |
| Timeout manager | Pending requests are keyed by `WalletSignRequestID` and expire at `WalletRequest.expiryDate`. |

## Direct SDK Adapters

| Test | Expected result |
| --- | --- |
| Coinbase | Direct Coinbase adapter can connect, request, disconnect, and report typed unavailable errors when unconfigured. |
| MetaMask | Direct MetaMask adapter can connect, request, disconnect, and report typed unavailable errors when unconfigured. |
| Privy | Privy adapter is treated as embedded-wallet/auth infrastructure, not generic wallet discovery. |
| Dynamic | Dynamic adapter is treated as embedded-wallet/auth infrastructure, not generic wallet discovery. |
| Solana | Solana adapter accepts Solana requests only and rejects EVM requests with typed unsupported-chain errors. |

## Host App Configuration

| Test | Expected result |
| --- | --- |
| Reown project ID | Host app supplies the Reown project ID through adapter configuration. |
| Native callback scheme | The host app registers the callback scheme used by wallet redirects. |
| Query schemes | `LSApplicationQueriesSchemes` includes every wallet deep-link scheme the host wants to probe with `canOpenURL`. |
| URL opening adapter | Platform URL opening remains owned by the host app. |
| QR fallback | If no wallet can be opened, the app shows the returned QR payload. |

## Manual Live-Wallet Suite

| Wallet | Required smoke tests |
| --- | --- |
| MetaMask | Connect, reject, disconnect, restore, `personal_sign`, typed-data sign, switch/add chain. |
| Rainbow | Connect through Reown/WalletConnect, reject, disconnect, restore, `personal_sign`. |
| Coinbase Wallet | Connect through Reown and direct Coinbase adapter, reject, disconnect, `personal_sign`. |
| Phantom | Connect through Reown/WalletConnect or deep link, reject, Solana sign message. |
| Rabby | Connect through Reown/WalletConnect or deep link, reject, EVM sign request. |
