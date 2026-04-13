# P0-803 Privacy + security checklist

## Status

Completed for the current Phase 0 release-readiness slice.

## Reviewed Surface Area

- shell account entry and QR scan flows
- account persistence and chain-scoped local data
- search history persistence
- receipt logging and payload sanitization
- external-link launching and trust labeling
- provider-backed ENS and NFT network surfaces
- music/audio remote download handling

## Checklist

### 1. Identity and account input handling

- [x] Manual address entry is normalized and strictly validated before persistence.
- [x] QR scans reuse the same validation contract before account activation.
- [x] Unsupported ENS input is rejected explicitly in the entry flow instead of being half-accepted.
- [ ] Checksum-display UX and richer phishing-resistant identity presentation remain deferred follow-on work.

Reviewed in:

- `Accounts/AccountStore.swift`
- `Aura/Auth/QRScannerView.swift`

### 2. Local persistence scope and retention

- [x] Persisted wallet identity is limited to read-only account addresses and metadata needed for shell behavior.
- [x] Search history is scoped per normalized account and capped per account.
- [x] Search history retention can now be cleared through the consolidated settings-driven privacy reset flow.
- [x] ENS cache retention is local and explicit, and it is now included in the consolidated privacy reset flow.

Reviewed in:

- `Accounts/AccountStore.swift`
- `Aura/Search/SearchHistoryStore.swift`
- `Networking/ENSResolutionService.swift`

### 3. Receipt and diagnostics privacy

- [x] Receipt payload sanitization now uses typed payload fields with explicit sensitivity metadata instead of relying only on guessed key names.
- [x] Receipt sanitization redacts, hashes, truncates, or structurally sanitizes values by sensitivity and value kind.
- [x] External-link receipts record provenance without keeping the raw outbound URL.
- [x] Unknown strings default closed and are treated as suspicious until explicitly classified by the emitting payload builder.

Reviewed in:

- `Receipts/DefaultReceiptPayloadSanitizer.swift`
- `Aura/Newsfeed/Components/OpenSeaLink.swift`

### 4. Secrets and provider configuration

- [x] Provider API keys now resolve from `Info.plist` only, with intended build-time injection from xcconfig.
- [x] Secret loading stays inside a dedicated configuration seam rather than leaking through UI code.
- [x] Release builds now fail fast at app launch if required provider keys are not present.

Reviewed in:

- `Networking/Secrets.swift`

### 5. Untrusted input and outbound actions

- [x] QR scanning is labeled as a scan/trust-sensitive action.
- [x] External NFT destinations are explicit and labeled before launch.
- [x] Unsupported or invalid scanned values surface user-facing errors instead of silently mutating shell state.
- [x] Trust labeling now covers the reviewed provider-backed balance and token surfaces, not only links and scans.

Reviewed in:

- `Aura/Auth/QRScannerView.swift`
- `Aura/Newsfeed/Components/OpenSeaLink.swift`

### 6. Network and media handling

- [x] NFT fetches validate account format before making provider calls.
- [x] Retry logic is bounded and cancellation-aware.
- [x] Audio downloads use temporary files and clean up stale downloaded files on replacement or stale-load cancellation.
- [ ] Audio temp-file lifecycle still deserves a dedicated lifecycle review for app termination and background-edge cases.

Reviewed in:

- `Networking/NFTFetcher.swift`
- `MusicApp/AI/Audio Engine/AudioEngine.swift`

### 7. Reset and deletion behavior

- [x] Receipts have a dedicated reset seam.
- [x] Settings now exposes a consolidated privacy reset that clears receipts, search history, ENS cache, gas cache, and persisted token holdings together.

Reviewed in:

- `Receipts/ReceiptResetService.swift`
- `Aura/Search/SearchHistoryStore.swift`
- `Networking/ENSResolutionService.swift`

## Findings

### Accepted for Phase 0

- Account entry is read-only and validation-first, which keeps the highest-risk write path narrow.
- Search history is scoped and size-limited instead of becoming a global activity exhaust log.
- Receipt logging already includes meaningful redaction for the most obvious sensitive payload classes.
- External outbound actions are explicit and trust-labeled in the reviewed NFT/detail surfaces.

### Explicit deferrals

1. Perform a focused lifecycle review of audio temp-file cleanup outside the active replacement/cancellation path.
2. Extend trust-label rollout further if additional provider-backed surfaces land beyond the currently reviewed token and balance paths.

## Validation

- The checklist is concrete enough to audit against real files and active surfaces.
- Reviewed surfaces and deferrals are explicit.
- Follow-on work is recorded as separate hardening, not misrepresented as already solved by this ticket.
