# AuraPlay Phase 3 Tickets

**Phase 3 — Storage Resolution Utilities**  
**6 Tickets** · **12 hrs Total Estimate** · **v1.0** · **April 2026**

## Phase Purpose

A pure, stateless URL resolver that normalises IPFS, Arweave, and HTTP URIs into playable HTTPS URLs. Zero network calls inside the resolver itself. No database access. No SwiftData. Fully testable with fixture inputs before any NFT data exists. Blocks Phases 4, 5, and 6.

## Scheme Coverage

| Scheme | Handled In | Example Input -> Output | Returns nil When |
| --- | --- | --- | --- |
| `ipfs://` and `/ipfs/` | P3-002 | `ipfs://QmABC` -> `https://cloudflare-ipfs.com/ipfs/QmABC` | Empty CID, traversal, > 512 chars |
| `ar://` | P3-003 | `ar://TX43chars` -> `https://arweave.net/TX43chars` | Not 43 chars, invalid base64url |
| `http://` | P3-004 | `http://x.com/t.mp3` -> `https://x.com/t.mp3` | Empty host, dangerous port |
| `https://` | P3-004 | `https://x.com/t.mp3` -> unchanged | Empty host, malformed URL |
| `data:` | P3-004 | `data:audio/mpeg;base64,...` -> `file:///tmp/auraplay_XXXX.mp3` | Bad base64, > 50 MB |
| Anything else | P3-001 | `ftp://`, `xyz://`, empty string -> nil | Always |

## Phase Summary

| Field | Value |
| --- | --- |
| Implementation Status | Complete in `MusicFeature/Sources/MusicFeature/Services/StorageResolution/` |
| Total Tickets | 6 |
| Ticket Types | 6 Task · 0 Spike · 0 Chore |
| P0 Tickets | 3 (`URLResolver` skeleton, IPFS handler, Arweave handler) |
| Total Estimate | 12 hrs |
| Key Constraint | `resolve()` is synchronous, bounded, no network, no SwiftData, and no I/O except the documented `data:` temp-file write |
| Phase Gate | All 58 tests in P3-006 pass; 100% branch coverage on resolver files |
| Parallel Potential | P3-002, P3-003, P3-004 can run in parallel after P3-001 merges; P3-005 starts after P3-002 and P3-003 merge |

## Shipping Validation

Current implementation files:

- `AuraPlayStorageResolutionConfiguration.swift`
- `URIScheme.swift`
- `URLResolver.swift`
- `GatewayFallbackChain.swift`
- `AuraPlayError.mediaResolution(String)`
- `AuraPlayDependencies.urlResolver`
- `MusicAssembly` live resolver wiring

Validation completed on June 7, 2026:

- `AuralisTests/AuraPlayStorageResolutionShipTests` passed, 3/3.
- `MusicFeatureTests/StorageResolutionTests` passed, 12/12.
- Full `MusicFeatureTests` passed, 28/28.
- `AuralisTests` passed through the `Auralis-Full` test plan.
- Full Xcode project build succeeded.
- Build log showed `URLResolver`, `URIScheme`, `GatewayFallbackChain`, and `AuraPlayStorageResolutionConfiguration` compiled with no emitted warnings.

The broader local-package sweep found unrelated package test debt outside Phase 3 storage resolution. That follow-up is tracked in `Phase3-Followup-Package-Test-Restoration.md` and does not reopen this phase.

The Phase 3 code and tests are present, build-clean, and validated for the shipping storage-resolution seam.

## Existing-Code Alignment

Phase 3 should reuse current project seams where they exist:

- Existing legacy URL helpers: `URLConverter.convertToPreferredHTTPS`, `URL.toPinataGatewayURL()`, `URL.sanitizedRemoteMediaURL(from:)`, `URIConfig`, `URIFormat`, and `NormalizedResource` already describe useful behavior, but they live in the app target or duplicated presentation support. Treat them as compatibility references and regression fixtures, not as the new `MusicFeature` implementation.
- Existing configuration seam: `AuraPlayModuleConfiguration.live(infoDictionary:)` is the current MusicFeature config surface. Do not introduce a global `AppConfig`. Use a focused `AuraPlayStorageResolutionConfiguration` value for gateway URLs and pass it through AuraPlay composition.
- Existing DI seam: the repo uses `MusicAssembly` and `AuraPlayDependencies`, not `DependencyValues`.
- Existing error seam: AuraPlay uses `AuraPlayError`. Add `AuraPlayError.mediaResolution(String)` for this phase rather than a separate public media-resolution error enum.
- Existing test network seam: `AuralisTestSupport.URLProtocolMock` and `URLSession.mocked(_:)` already provide no-network URLSession tests. Use those before creating a separate mock session type.
- Existing clock precedent: `AuralisShellCore` has `ShellClock`, but MusicFeature should own its own tiny clock closure or protocol for gateway-health expiry to avoid coupling storage resolution to shell internals.

## Create Vs Reuse For Phase 3

| Object / Concern | Decision |
| --- | --- |
| `URIScheme` | Create in `MusicFeature`; no existing package-level classifier covers the Phase 3 cases. |
| `URLResolver` | Create in `MusicFeature`; existing app/NFTKit helpers are reference behavior only. |
| Gateway configuration | Create `AuraPlayStorageResolutionConfiguration` in `MusicFeature`; this is the most logical home because gateway choice belongs to storage resolution, not the bundle-contract snapshot. |
| `GatewayFallbackChain` | Create in `MusicFeature`; no existing retry/health-cache actor matches this role. |
| HEAD client abstraction | Reuse `URLSession` directly with `URLSession.mocked(_:)` first; create `GatewayHEADClient` only if tests or actor isolation need a narrower seam. |
| Live HEAD client | Usually no separate object if `URLSession` injection is enough; otherwise create `URLSessionGatewayHEADClient`. |
| Mock HEAD client | Reuse `AuralisTestSupport.URLProtocolMock`; create a small fake only if `GatewayHEADClient` is introduced. |
| Media-resolution errors | Extend `AuraPlayError` with `case mediaResolution(String)`. |
| Gateway URL normalization | Create small private helpers in the storage-resolution files. |
| Dangerous-port validation | Create small private helper in `URLResolver`. |
| MIME extension mapping | Create small private helper in `URLResolver`. |
| SHA256 temp filename | Create small private helper using `CryptoKit`; existing hash helpers are app-target-specific. |
| Health-cache clock | Create a tiny MusicFeature-owned `() -> Date` injection or local protocol; do not import shell clock just for this. |

## Ticket Summary

| ID | Title | Type | Priority | Estimate | Depends |
| --- | --- | --- | --- | --- | --- |
| P3-001 | `URLResolver` struct — skeleton, URI scheme detection, MusicFeature configuration, and DI wiring | TASK | P0 | 2 hrs | P1-001 (project), P1-004 (assembly DI), P1-007 (`AuraPlayError`) |
| P3-002 | IPFS resolution — gateway rewrite, CID validation, and dual-scheme handling | TASK | P0 | 2 hrs | P3-001 (`URLResolver` skeleton and `URIScheme.ipfsNative` / `.ipfsPath` cases) |
| P3-003 | Arweave resolution — `ar://` scheme handler and TX ID validation | TASK | P0 | 1.5 hrs | P3-001 (`URLResolver` skeleton and `URIScheme.arweave` case) |
| P3-004 | HTTP enforcement and `data:` URI decoder | TASK | P1 | 2 hrs | P3-001 (`URLResolver` skeleton, `URIScheme.http` / `.https` / `.dataURI` cases) |
| P3-005 | Gateway fallback chain — multi-gateway retry coordinator for IPFS and Arweave | TASK | P1 | 2 hrs | P3-001, P3-002, P3-003 |
| P3-006 | Comprehensive test suite — 50+ unit tests covering all schemes, edge cases, and security inputs | TASK | P1 | 2.5 hrs | P3-001, P3-002, P3-003, P3-004, P3-005 |

## Ticket Details

## P3-001 — `URLResolver` Struct Skeleton, URI Scheme Detection, MusicFeature Configuration, And DI Wiring

**Type:** TASK  
**Priority:** P0  
**Estimate:** 2 hrs  
**Depends on:** P1-001 (project), P1-004 (assembly DI), P1-007 (`AuraPlayError`)  
**Blocks:** P3-002, P3-003, P3-004, P3-005 (all scheme handlers extend this skeleton)

### Description

Establish the `URLResolver` struct, the `URIScheme` enum that classifies every incoming string, the MusicFeature-owned gateway configuration surface, and the dependency wiring. This ticket produces a working resolver skeleton that returns nil for all inputs — each scheme handler fills in real behaviour in the tickets that follow. Nothing in this ticket makes a network call or touches the file system.

### Technical Notes

- `URLResolver` is a struct (value type, not a class or actor). It has no mutable runtime state. Gateway inputs come from a MusicFeature-owned configuration value. It has exactly one public method: `func resolve(_ uri: String) -> URL?`.
- `resolve()` is synchronous, bounded, has no network I/O, and uses no async/await. It is safe to call from any thread or actor. Disk I/O is forbidden except for the documented `data:` URI temp-file write added in P3-004.
- `URIScheme` enum — exhaustive, internal:

```swift
case ipfsNative(cid: String)        // "ipfs://<CID>"
case ipfsPath(cid: String)          // "/ipfs/<CID>" or "ipfs/<CID>"
case arweave(txID: String)          // "ar://<TX_ID>"
case http(url: URL)                 // "http://..."
case https(url: URL)                // "https://..."
case dataURI(mimeType: String, isBase64: Bool, body: String) // "data:..."
case unknown                        // anything else
```

- Static `func URIScheme.detect(from raw: String) -> URIScheme` is the classifier. It is called by `resolve()` before dispatching to a handler.
- Classification handles leading/trailing whitespace via `trimmingCharacters(in: .whitespacesAndNewlines)`.

Detection rules, evaluated in order:

1. Empty or whitespace-only string -> `.unknown`
2. Lowercased prefix `"ipfs://"` -> `.ipfsNative(cid: everything after "ipfs://")`
3. Lowercased prefix `"/ipfs/"` or `"ipfs/"` (no scheme) -> `.ipfsPath(cid: ...)`
4. Lowercased prefix `"ar://"` -> `.arweave(txID: everything after "ar://")`
5. Lowercased prefix `"data:"` -> parse MIME type, base64 flag, body -> `.dataURI`
6. Valid URL with scheme `"http"` -> `.http(url:)`
7. Valid URL with scheme `"https"` -> `.https(url:)`
8. Anything else -> `.unknown`

In this skeleton ticket, `resolve()` returns nil for every case. Subsequent tickets replace nil with real URLs for each case.

Configuration: add an `AuraPlayStorageResolutionConfiguration` value in `MusicFeature`. This is preferred over adding gateway fields to `AuraPlayModuleConfiguration` because storage gateway choice is a storage-resolution concern, while `AuraPlayModuleConfiguration` currently snapshots app bundle capabilities. Defaults:

- `ipfsGatewayURL`: `https://cloudflare-ipfs.com`
- `arweaveGatewayURL`: `https://arweave.net`
- fallback IPFS gateways: `https://ipfs.io`, `https://dweb.link`
- fallback Arweave gateways: `https://arweave.dev`

Dependency registration: use the existing assembly pattern. Do not add `DependencyValues`. Add `URLResolver` to `AuraPlayDependencies` in P3-001 even before UI or services consume it, and construct it in `MusicAssembly` from `AuraPlayStorageResolutionConfiguration.liveDefault`.

Register `URLResolver` in the `MusicFeature` package so it can be imported by the app target and `MusicFeatureTests`.

### Acceptance Criteria

- `URLResolver.resolve("")` returns nil (empty string).
- `URLResolver.resolve("   \t\n  ")` returns nil (whitespace-only).
- `URIScheme.detect(from: "ipfs://Qm123") == .ipfsNative(cid: "Qm123")`.
- `URIScheme.detect(from: "/ipfs/Qm123") == .ipfsPath(cid: "Qm123")`.
- `URIScheme.detect(from: "ar://abc123") == .arweave(txID: "abc123")`.
- `URIScheme.detect(from: "https://example.com/image.png") == .https(url: URL("https://example.com/image.png"))`.
- `URIScheme.detect(from: "IPFS://Qm123") == .ipfsNative` (case-insensitive prefix detection confirmed).
- `AuraPlayDependencies` exposes the configured `URLResolver`.
- `MusicAssembly.makeMusicFeatureDependencies(...)` wires the live resolver using `AuraPlayStorageResolutionConfiguration.liveDefault`.
- Build succeeds with zero warnings; SwiftLint passes.

## P3-002 — IPFS Resolution, Gateway Rewrite, CID Validation, And Dual-Scheme Handling

**Type:** TASK  
**Priority:** P0  
**Estimate:** 2 hrs  
**Depends on:** P3-001 (`URLResolver` skeleton and `URIScheme.ipfsNative` / `.ipfsPath` cases)  
**Blocks:** P3-005 (fallback chain wraps IPFS resolution), Phases 4, 5, 6 (all use `URLResolver` for NFT media)

### Description

Implement the IPFS handler inside `URLResolver` — the most common URI scheme encountered from NFT metadata. Both `ipfs://` and bare `/ipfs/` path prefixes must be resolved to an HTTPS gateway URL. The gateway comes from the MusicFeature storage-resolution configuration so users can supply their own self-hosted or pinning-service endpoint later. Use the existing `URL.toPinataGatewayURL()` behavior and `URLExtensionTests` as compatibility references, but do not depend on app-target helpers from `MusicFeature`.

### Technical Notes

- Handler is a private method on `URLResolver`: `func resolveIPFS(cid: String) -> URL?`.
- Both `.ipfsNative` and `.ipfsPath` cases feed into the same handler — their only difference is the prefix stripped by `URIScheme.detect`.
- Resolution rule: replace scheme and authority with the configured primary IPFS gateway.

```text
Input:  "ipfs://QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco"
Output: "https://cloudflare-ipfs.com/ipfs/QmXoypizjW3WknFiJnKLwHCnL72vedxjQkDDP1mXWo6uco"
```

- Gateway URL is read from `AuraPlayStorageResolutionConfiguration.ipfsGatewayURL`. Default: `"https://cloudflare-ipfs.com"`.
- The gateway URL must end without a trailing slash — strip it if present before appending `/ipfs/<CID>`.

CID validation — `resolveIPFS` returns nil for:

- Empty CID string after stripping the prefix.
- CID containing path traversal characters: `..`, `%2e%2e` (case-insensitive URL-encoded variant).
- CID containing whitespace.
- CID longer than 512 characters (guard against pathologically long inputs).

CID sub-path support: NFT metadata sometimes includes a sub-path after the CID, e.g. `"ipfs://QmABC.../metadata.json"`. The handler must preserve everything after the CID root as a path component on the gateway URL.

```text
Input:  "ipfs://QmABC.../metadata.json"
Output: "https://cloudflare-ipfs.com/ipfs/QmABC.../metadata.json"
```

URL construction: use `URLComponents` to build the output — never string concatenation with user-supplied CIDs.

IPNS support (v1 CIDs starting with `"k"`): treated identically to CIDv0/v1 — the gateway handles IPNS resolution transparently.

### Acceptance Criteria

- `resolve("ipfs://QmXoy...")` returns URL with host `"cloudflare-ipfs.com"` and path `"/ipfs/QmXoy..."`.
- `resolve("/ipfs/QmXoy...")` returns the same URL (both prefixes resolve identically).
- `resolve("ipfs://QmABC.../metadata.json")` preserves the sub-path on the gateway URL.
- `resolve("ipfs://")` returns nil (empty CID).
- `resolve("ipfs://../malicious")` returns nil (path traversal blocked).
- `resolve("ipfs://" + String(repeating: "a", count: 513))` returns nil (CID too long).
- Injecting a custom gateway `"https://my-gateway.io"` produces URLs with host `"my-gateway.io"`.
- URL is constructed via `URLComponents` — no string concatenation with CID value (code review / lint rule).

## P3-003 — Arweave Resolution, `ar://` Scheme Handler, And TX ID Validation

**Type:** TASK  
**Priority:** P0  
**Estimate:** 1.5 hrs  
**Depends on:** P3-001 (`URLResolver` skeleton and `URIScheme.arweave` case)  
**Blocks:** P3-005 (fallback chain), Phases 4, 5, 6

### Description

Implement the Arweave handler. Arweave is the second most common decentralised storage protocol in music NFT projects (heavily used by Sound.xyz, Catalog, and Zora). The `ar://` scheme is resolved to the public Arweave gateway in the same pattern as IPFS.

### Technical Notes

- Handler: `private func resolveArweave(txID: String) -> URL?`.
- Resolution rule:

```text
Input:  "ar://lnGaimJ0PbDfBEAKqBGBJZ3rlrGLVARRKFbNNe9SLHY"
Output: "https://arweave.net/lnGaimJ0PbDfBEAKqBGBJZ3rlrGLVARRKFbNNe9SLHY"
```

- Gateway URL: `AuraPlayStorageResolutionConfiguration.arweaveGatewayURL`. Default: `"https://arweave.net"`. Trailing slash stripped before use.

TX ID validation — returns nil for:

- Empty TX ID.
- TX ID containing characters outside the Arweave base64url alphabet: `[A-Za-z0-9_-]`. Arweave TX IDs are exactly 43 characters of base64url.
- TX ID not exactly 43 characters (Arweave TX IDs have a fixed length).
- TX ID containing path traversal `..` or `%2e%2e`.

Sub-path support: Arweave manifests sometimes include a path component after the TX ID, e.g. `"ar://TX123.../track.mp3"`. Preserve sub-path on the gateway URL, same as IPFS handler.

URL construction: `URLComponents`. Never string concatenation with user-supplied TX IDs.

Unlike IPFS, there is no bare path variant (no `/ar/` prefix exists in the wild). Only the `ar://` scheme is handled.

### Acceptance Criteria

- `resolve("ar://lnGaimJ0PbDfBEAKqBGBJZ3rlrGLVARRKFbNNe9SLHY")` returns URL with host `"arweave.net"` and correct path.
- `resolve("ar://TX123.../track.mp3")` preserves sub-path on the gateway URL.
- `resolve("ar://")` returns nil (empty TX ID).
- `resolve("ar://not43chars")` returns nil (wrong length).
- `resolve("ar://abc!@#def...")` returns nil (invalid base64url characters).
- `resolve("ar://../escape")` returns nil (path traversal blocked).
- Injecting custom gateway `"https://my-arweave.io"` produces URLs with host `"my-arweave.io"`.

## P3-004 — HTTP Enforcement And `data:` URI Decoder

**Type:** TASK  
**Priority:** P1  
**Estimate:** 2 hrs  
**Depends on:** P3-001 (`URLResolver` skeleton, `URIScheme.http` / `.https` / `.dataURI` cases)  
**Blocks:** P3-006 (test suite covers these handlers), Phases 4, 5, 6

### Description

Two distinct handlers in one ticket because both are small. The HTTP-to-HTTPS rewrite protects against accidental cleartext media fetches. The `data:` URI decoder handles the minority of NFTs that embed their media inline as a base64-encoded data URI — common in small on-chain generative art pieces.

### Technical Notes

#### HTTP Enforcement

- Handler: `private func resolveHTTP(_ url: URL) -> URL?`.
- Rule: if the URL scheme is `"http"`, return the same URL with scheme replaced by `"https"`. If scheme is already `"https"`, return as-is.

```text
Input:  "http://example.com/track.mp3"
Output: "https://example.com/track.mp3"
```

- Implementation: use `URLComponents(url: url, resolvingAgainstBaseURL: false)`, set `components.scheme = "https"`, return `components.url`.
- Return nil if `URLComponents` fails to parse the input (malformed URL).
- Return nil if the host is empty after parsing — bare `"http://"` or `"https://"` with no host are invalid.
- Return nil if the URL contains a non-standard port that would be dangerous in a `WKWebView` context (ports 0, 1–1023 excluding 80 and 443). If logging is wired here, use the existing `AuraPlayLogging` levels (`.info` or `.error`) unless a separate `.warning` level is added deliberately.

#### `data:` URI Decoder

- Handler: `private func resolveDataURI(mimeType: String, isBase64: Bool, body: String) -> URL?`.
- `data:` URI format: `"data:[<mediatype>][;base64],<data>"`.
- If `isBase64 == true`: decode body via `Data(base64Encoded: body, options: .ignoreUnknownCharacters)`. Return nil if decoding fails.
- If `isBase64 == false`: body is URL-percent-encoded text. Decode via `body.removingPercentEncoding`. Convert to UTF-8 `Data`.
- Write decoded `Data` to a temp file in `FileManager.default.temporaryDirectory` with a deterministic filename: `"auraplay_data_(SHA256(of: body).hexPrefix(8)).(fileExtension(for: mimeType))"`.

File extension map:

| MIME Type | Extension |
| --- | --- |
| `audio/mpeg` | `mp3` |
| `audio/flac` | `flac` |
| `video/mp4` | `mp4` |
| `image/png` | `png` |
| `image/svg+xml` | `svg` |
| unknown MIME type | `bin` |

- Return the `file://` URL of the written temp file.
- Temp file lifetime: files in `temporaryDirectory` are managed by the OS and are cleared on low-storage events. Callers must not assume the file persists across app restarts.
- Size guard: return nil if the decoded `Data` exceeds 50 MB. `data:` URIs above this size are pathological and indicate a malformed or malicious input.
- This is the one place in `URLResolver` that performs disk I/O. It is still synchronous — `FileManager` temp writes are fast and the 50 MB guard prevents abuse. Document in code comments that this is the single I/O exception and the reason it is acceptable.

### Acceptance Criteria

- `resolve("http://example.com/track.mp3")` returns URL with scheme `"https"`.
- `resolve("https://example.com/track.mp3")` returns the URL unchanged.
- `resolve("http://")` returns nil (empty host).
- `resolve("http://example.com:22/track.mp3")` returns nil (non-standard dangerous port).
- `resolve("data:audio/mpeg;base64,<valid_base64>")` returns a `file://` URL; the file exists and contains the decoded bytes.
- `resolve("data:audio/mpeg;base64,!!!notbase64!!!")` returns nil (invalid base64).
- `resolve("data:audio/mpeg;base64,<50MB+>")` returns nil (size guard).
- Calling `resolve()` twice with the same `data:` URI returns a URL to the same deterministic filename (idempotent — no duplicate temp files).

## P3-005 — Gateway Fallback Chain, Multi-Gateway Retry Coordinator For IPFS And Arweave

**Type:** TASK  
**Priority:** P1  
**Estimate:** 2 hrs  
**Depends on:** P3-001, P3-002, P3-003  
**Blocks:** Phase 5 (NFT discovery fetches metadata via the fallback chain), Phase 6 (audio engine fetches media via the fallback chain)

### Description

`URLResolver.resolve()` returns a single URL — the primary gateway. This ticket implements `GatewayFallbackChain`, a separate actor that sits above `URLResolver` in the network stack. It tries the primary URL and, on failure, retries with alternative gateway URLs. `URLResolver` itself stays pure and synchronous; the retry logic lives here.

### Technical Notes

- `GatewayFallbackChain` is an actor (not a struct) because it maintains a short-term in-memory cache of gateway health to avoid hammering a known-dead gateway on every request within a session.
- `GatewayConfig`: the ordered list of gateway URLs per protocol, loaded from the MusicFeature storage-resolution configuration:

```swift
static let ipfsGateways: [String] = [
    configuration.ipfsGatewayURL, // user-configured primary (default: cloudflare-ipfs.com)
    "https://ipfs.io",         // Protocol Labs public gateway
    "https://dweb.link",       // Protocol Labs alt gateway
]

static let arweaveGateways: [String] = [
    configuration.arweaveGatewayURL, // user-configured primary (default: arweave.net)
    "https://arweave.dev",      // secondary
]
```

`GatewayFallbackChain.resolve(_ uri: String) async throws -> URL` is the async API used by all network callers:

1. Call `URLResolver.resolve(uri)` to get the primary URL. Throw `AuraPlayError.mediaResolution("Unsupported media URI scheme: \(uri)")` if nil.
2. Try fetching a HEAD request to the primary URL through an injected URLSession-backed client, with an 8-second timeout. If HTTP 200–299: return the primary URL.
3. If the primary fails: determine which gateway list applies (`ipfsGateways` or `arweaveGateways`). Iterate remaining gateways in order.
4. For each fallback gateway: rewrite the URL to use that gateway (same path, new host), retry HEAD request.
5. If all gateways fail: throw `AuraPlayError.mediaResolution("All media gateways failed for URI: \(uri)")`.

HEAD request rationale: HEAD is lightweight (no body download). It confirms the resource exists and the gateway is reachable without fetching the full media file.

Gateway health cache: maintain a `[String: Date]` dictionary of gateway URLs that have failed within the last 60 seconds. Skip these on the retry loop without making a network call — reduces latency when a gateway is down for an extended period.

- `http://` and `https://` URIs bypass the gateway logic entirely. `GatewayFallbackChain` passes them straight through after the HEAD confirmation.
- `data:` URIs bypass the gateway logic entirely. Return the URL from `URLResolver.resolve()` directly without any network check.
- Register `GatewayFallbackChain` through the existing assembly pattern only when a live caller needs it. Tests should use `AuralisTestSupport.URLProtocolMock` / `URLSession.mocked(_:)` to return pre-programmed success/failure responses without making real network calls. If actor isolation or call-count assertions become awkward with raw `URLSession`, add a tiny `GatewayHEADClient` protocol inside MusicFeature, but do not create a mock object when `URLSession.mocked(_:)` is enough.

Error additions for this phase:

```swift
AuraPlayError.mediaResolution(String)
```

### Acceptance Criteria

- `GatewayFallbackChain.resolve("ipfs://QmABC...")` returns the primary gateway URL when the mocked URLSession returns 200 for the first attempt.
- When primary returns 503, fallback returns 200: `resolve()` returns the fallback gateway URL.
- When all gateways return 503: `resolve()` throws `AuraPlayError.mediaResolution` with an all-gateways-failed message.
- A gateway URL added to the health cache (failed within 60 s) is skipped without a URLSession call — verified by asserting mocked URLSession call count.
- `resolve("https://example.com/track.mp3")` returns the URL without attempting any gateway substitution.
- `resolve("data:audio/mpeg;base64,...")` returns the `file://` URL without making any network call.
- `resolve("xyz://unknown")` throws `AuraPlayError.mediaResolution` with an unsupported-scheme message.

## P3-006 — Comprehensive Test Suite Covering All Schemes, Edge Cases, And Security Inputs

**Type:** TASK  
**Priority:** P1  
**Estimate:** 2.5 hrs  
**Depends on:** P3-001, P3-002, P3-003, P3-004, P3-005  
**Blocks:** Phase 3 acceptance gate — phase cannot close until all tests pass

### Description

Write the full test suite for the storage resolution layer. Every branch in `URLResolver`, `GatewayFallbackChain`, and `URIScheme.detect` must be exercised. The goal is 100% branch coverage on these files. Zero network calls are made in any test — gateway calls use `AuralisTestSupport.URLProtocolMock` / `URLSession.mocked(_:)`, or a tiny `GatewayHEADClient` test double only if P3-005 introduces that protocol.

### Technical Notes

- Test target: `MusicFeatureTests`. No new target needed.
- All tests use Swift Testing (`@Test`, `#expect`). All tests are synchronous except `GatewayFallbackChain` tests which use async `@Test`.
- All tests instantiate `URLResolver` with fixture gateway configuration and use `URLSession.mocked(_:)` or the MusicFeature-owned HEAD-client test double. No real network calls anywhere.

#### URIScheme Detection Tests (12 tests)

- `detect("") == .unknown`
- `detect("   ") == .unknown` (whitespace)
- `detect("ipfs://QmABC") == .ipfsNative(cid: "QmABC")`
- `detect("IPFS://QmABC") == .ipfsNative` (case-insensitive)
- `detect("/ipfs/QmABC") == .ipfsPath(cid: "QmABC")`
- `detect("ipfs/QmABC") == .ipfsPath` (no leading slash variant)
- `detect("ar://TX123...43chars") == .arweave(txID: "TX123...43chars")`
- `detect("http://example.com") == .http`
- `detect("https://example.com") == .https`
- `detect("data:audio/mpeg;base64,abc") == .dataURI(mimeType: "audio/mpeg", isBase64: true, ...)`
- `detect("data:text/plain,hello") == .dataURI(isBase64: false, ...)`
- `detect("ftp://oldprotocol.com") == .unknown`

#### IPFS Handler Tests (10 tests)

- Valid CIDv0 (`Qm...`) resolves to primary gateway URL with correct path.
- Valid CIDv1 (`bafy...`) resolves correctly.
- IPNS key (`k51...`) resolves — treated same as CID.
- Sub-path `"ipfs://QmABC.../metadata.json"` preserves path component.
- `"ipfs://"` (empty CID) returns nil.
- `"ipfs://  "` (whitespace CID) returns nil.
- `"ipfs://../etc/passwd"` returns nil (path traversal).
- `"ipfs://%2e%2e/escape"` returns nil (URL-encoded path traversal).
- CID of 513 characters returns nil.
- Custom gateway injection produces correct host in output URL.

#### Arweave Handler Tests (8 tests)

- Valid 43-char base64url TX ID resolves to `arweave.net` with correct path.
- Sub-path `"ar://TX.../track.mp3"` preserves path component.
- `"ar://"` (empty TX ID) returns nil.
- `"ar://short"` (under 43 chars) returns nil.
- `"ar://" + String(repeating: "a", count: 44)` (over 43 chars) returns nil.
- `"ar://!!!invalid!!characters!!!!!!!!!!!!!!!"` returns nil (non-base64url chars).
- `"ar://../escape"` returns nil (path traversal).
- Custom gateway injection produces correct host.

#### HTTP Enforcement Tests (7 tests)

- `"http://example.com/track.mp3"` resolves to same URL with `"https"` scheme.
- `"https://example.com/track.mp3"` resolves unchanged.
- `"http://"` (no host) returns nil.
- `"https://"` (no host) returns nil.
- `"http://example.com:22/file"` returns nil (dangerous port).
- `"http://example.com:80/file"` resolves (port 80 is allowed).
- `"http://example.com:443/file"` resolves (port 443 is allowed).

#### `data:` URI Tests (8 tests)

- Valid base64 audio `data:` URI resolves to `file://` URL; file exists and bytes match decoded input.
- Valid percent-encoded text `data:` URI resolves to `file://` URL with correct content.
- Invalid base64 body returns nil.
- `data:` URI exceeding 50 MB returns nil.
- MIME type `"audio/mpeg"` produces file with `.mp3` extension.
- MIME type `"video/mp4"` produces file with `.mp4` extension.
- Unknown MIME type produces file with `.bin` extension.
- Two calls with identical input return the same deterministic filename (idempotent).

#### GatewayFallbackChain Tests (8 tests)

- Primary gateway 200 -> returns primary URL; no fallback attempted (assert URLSession call count == 1).
- Primary 503 -> fallback 200 -> returns fallback URL.
- Primary 503 -> fallback 503 -> all gateways fail -> throws `AuraPlayError.mediaResolution`.
- Gateway in health cache (failed < 60 s ago) is skipped; URLSession not called for it.
- Health cache entry expires after 60 s -> gateway is retried (simulated by advancing mock clock).
- `https://` URI bypasses gateway substitution; URLSession called exactly once with original URL.
- `data:` URI returns `file://` URL with zero URLSession calls.
- Unsupported scheme `"xyz://"` throws `AuraPlayError.mediaResolution`.

#### Additional Edge Case Tests (5 tests)

- `resolve(nil-producing input)` never crashes — always returns nil or throws, never fatal errors.
- `resolve()` called concurrently from 50 `Task { }` blocks with different inputs produces correct results with no data races (Swift concurrency checker clean).
- `URLResolver` with missing gateway URL (empty string) falls back to hardcoded default `"https://cloudflare-ipfs.com"` gracefully.
- Unicode in IPFS sub-path (`"ipfs://QmABC.../文件.mp3"`) is correctly percent-encoded in the output URL.
- Extremely long URI (10,000 characters) does not cause a crash or excessive memory use.

### Acceptance Criteria

- All 58 tests pass on every CI run with zero flakiness.
- `URLResolver.swift`, `URIScheme.swift`, and `GatewayFallbackChain.swift` all show 100% branch coverage in Xcode coverage report.
- Zero network calls made during any test (mocked URLSession or HEAD-client call count assertions confirm this for all network-shaped tests).
- Swift concurrency data race detector reports zero issues on the concurrent-access test.
- Test suite runs in under 1 second (pure computation, no I/O delays).

— End of Phase 3 Tickets —
