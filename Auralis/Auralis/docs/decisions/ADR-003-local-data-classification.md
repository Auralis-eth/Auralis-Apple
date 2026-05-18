# ADR-003: Local Data Classification

## Status

Accepted.

## Context

Auralis persists several kinds of local data: app mode, pinned launcher actions, active wallet selection, account records, receipts, cache ownership, and credentials. Those values previously used a mix of `UserDefaults`, `@AppStorage`, SwiftData, Keychain, and transient view state without a single ownership rule.

## Decision

Local data is classified into three tiers:

- `publicPreference`: non-sensitive UI preferences. UserDefaults is allowed.
- `walletMetadata`: wallet identity, active wallet selection, chain selection, and wallet-scoped cache ownership. Use protected local storage or SwiftData model records with explicit privacy-reset behavior.
- `credential`: passwords, signing secrets, tokens, and future capability grants. Use Keychain only.

Current mappings:

| Value | Classification | Storage | Reset behavior |
|---|---|---|---|
| `app.mode` | `publicPreference` | UserDefaults via `ModeState` | Cleared/normalized with local preferences |
| `auralis.home.pinned-items.v1` | `publicPreference` | UserDefaults | Cleared with local preferences |
| `auralis.shell.selection.v1` | `walletMetadata` | Keychain | Cleared with local preferences |
| `EOAccount` | `walletMetadata` | SwiftData | Cleared or scoped by account operations/privacy reset |
| `WalletPasswordService/WalletPasswordAccount` | `credential` | Keychain | Cleared in credential reset phase |
| Transient navigation/presentation state | `publicPreference` | View state | Not persisted |

## Consequences

The active shell address and chain selection are no longer mirrored through UserDefaults. Harmless UI preferences can remain in UserDefaults, but every persisted value must have a classification entry in `LocalDataStoragePolicy` before new storage is introduced.
