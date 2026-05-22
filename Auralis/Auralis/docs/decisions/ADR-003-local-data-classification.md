# ADR-003: Local Data Classification

## Status

Accepted.

## Context

Auralis persists several kinds of local data: app mode, pinned launcher actions, active wallet selection, account records, receipts, cache ownership, and credentials. Those values previously used a mix of `UserDefaults`, `@AppStorage`, SwiftData, Keychain, and transient view state without a single ownership rule.

## Decision

Local data is classified into four tiers:

- `publicIdentifierMetadata`: public chain identifiers and derived mappings, such as Ethereum addresses, ENS names, and public chain data. These are not private secrets, but they still require explicit retention and reset behavior.
- `publicPreference`: non-sensitive UI preferences and bundled public client configuration. UserDefaults or bundle configuration is allowed when the value is not user-private.
- `walletMetadata`: wallet identity, active wallet selection, chain selection, and wallet-scoped cache ownership. Use protected local storage or SwiftData model records with explicit privacy-reset behavior.
- `credential`: passwords, signing secrets, tokens, and future capability grants. Use Keychain only.

Current mappings:

| Value | Classification | Storage | Reset behavior |
|---|---|---|---|
| `app.mode` | `publicPreference` | UserDefaults via `ModeState` | Cleared/normalized with local preferences |
| `auralis.home.pinned-items.v1` | `publicPreference` | UserDefaults | Cleared with local preferences |
| `Auralis.ENSResolutionCache.v1` | `publicIdentifierMetadata` | UserDefaults | Cleared with support caches |
| `AuralisReceiptIntegrityHeadService` | `walletMetadata` | Keychain | Cleared with transactional receipt data |
| `SearchHistoryRecord` | `walletMetadata` | SwiftData | Cleared with transactional wallet data |
| `ProviderKit.GasPriceCache.shared` | `publicIdentifierMetadata` | In-memory cache | Cleared with support caches |
| `AURALIS_ALCHEMY_API_KEY` | `publicPreference` | Info.plist bundle configuration | Not user-local; not cleared by privacy reset |
| `auralis.shell.selection.v1` | `walletMetadata` | Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Cleared with local preferences |
| `EOAccount` | `walletMetadata` | SwiftData | Cleared or scoped by account operations/privacy reset |
| `WalletPasswordService/WalletPasswordAccount` | `credential` | Keychain | Cleared in credential reset phase |
| Transient navigation/presentation state | `publicPreference` | View state | Not persisted |

## Consequences

The active shell address and chain selection are no longer mirrored through UserDefaults. Harmless UI preferences can remain in UserDefaults, and ENS/address mappings can remain in UserDefaults because they are public identifier metadata with a short retention TTL. That classification does not make them exempt from reset: privacy reset must clear the ENS cache, search history, receipt integrity heads, gas cache, pinned actions, and saved shell selection according to the policy table.

The shell-selection Keychain item intentionally uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Active address and chain are wallet metadata rather than signing credentials, but the shell can need the current scope after first unlock for app restoration, refresh coordination, deep-link replay, and other non-interactive work that may run while the device is locked. The `ThisDeviceOnly` suffix keeps that metadata off backups and device migration. This is a narrower threat-model choice than a migratable `AfterFirstUnlock` item and a more available choice than `WhenUnlockedThisDeviceOnly`; credentials still use stricter credential-specific Keychain policy. Privacy reset clears shell selection in the local preferences phase so the next launch returns to the default shell scope instead of restoring the previous active wallet.

Receipt integrity heads are wallet metadata because they bind each local receipt chain to a separately protected account head on this device. The receipt store hashes each payload, links each receipt to the previous per-account chain hash, and verifies the latest persisted chain hash against the Keychain head. That gives Auralis local tamper evidence for out-of-band mutation, deletion, rollback, and protected-head mismatch. It does not create externally enforceable proof by itself; production evidence beyond this device requires trusted infrastructure or signed receipt-head synchronization.

Every persisted or durable configuration value must have a classification entry in `LocalDataStoragePolicy` before new storage is introduced. Ethereum addresses and ENS mappings are public identifiers in Auralis, not private secrets, but their retention and reset contract must still be explicit.
