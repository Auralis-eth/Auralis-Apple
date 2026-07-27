# AuraPlay Phase 12 — Ecosystem

4 Tickets · 8 hrs Total Estimate · v1.0 · Updated July 2026

## Phase Purpose

Connect AuraPlay outward without changing its product contract: AuraPlay remains a read-only NFT media library and player inside Auralis, not a marketplace, price tracker, listing surface, or hosted social product.

This phase adds provenance transparency, share actions that use standard iOS mechanisms, creator aggregation that is explicit about wallet scope, and deep links that route through the app's existing shell. It has no backend of its own.

## Current Baseline

Already available:

- The shipping Music tab opens `MusicFeatureRootView`, which composes `LibraryRootView`.
- Library item browsing is built around `AuraPlayMediaItem`, `MediaItemQueryItem`, `AuraPlayMediaItemService`, `LibraryItemCell`, `LibraryGroupDetailView`, and `AuraPlayPlaylistService`.
- Current AuraPlay scope is `AuraPlayLibraryScope(accountAddress:chain:)`; most library and search behavior is intentionally active-wallet and active-chain scoped.
- Creator and collection grouping already exist through `AuraPlayGroupedLibraryIndex`, `LibraryCollectionGroup`, `LibraryCreatorGroup`, and `LibraryGroupKey`.
- Player and library context menus already share `AuraPlayPlayerContextMenuBuilder`.
- App-owned context actions already exist in `AuraPlayPlayerContextActions`: UIKit share sheet, Safari explorer opening, and pasteboard copy.
- Explorer URLs already route through `AuraPlayExplorerURLBuilder`, backed by `ExplorerAdapter` for EVM chains with a Solscan branch for Solana.
- The bundle already declares `auraplay` and `auralis` URL schemes, and `AuraPlayModuleConfiguration` validates those bundle requirements.
- Deep-link intake already flows through `MainAuraView.onOpenURL`, `AppDeepLinkParser`, `ShellStore.send(.deepLinkReceived)`, and `DefaultShellDeepLinkReplayer`. `AppRouter` is a navigation store, not the URL parser.

Known gaps this phase should close:

- There is no dedicated provenance sheet. The current user-facing actions are share, view on explorer, and copy contract.
- `AuraPlayExplorerURLBuilder` is app-target internal and currently tested for external link construction, but there is no package-facing provenance model.
- Share actions for player/library items exist; playlist and collection share links are not formalized as reusable URL-generation policy.
- App deep links currently support account, NFT, ERC-20 token, and receipt routes. They do not yet support AuraPlay playlist, music collection, or creator destinations.
- `MusicRoute` currently has item, collection, and video cases. It has no playlist or creator route, and collection routes use a display key/title rather than a durable share URL payload.
- Cross-wallet creator aggregation is not supported by the current `AuraPlayLibraryScope` query contract. Implementing it requires an explicit service method or query scope extension.

## Non-Negotiable Invariants

1. No marketplace, pricing, listing, floor-price, offer, trading, or transactional data is fetched or displayed.
2. AuraPlay remains read-only with respect to NFT ownership and chain state.
3. `MusicFeature` owns reusable presentation contracts and SwiftUI views; app-owned integrations stay in the app target.
4. URL opening, UIKit share sheets, pasteboard writes, haptics, and Safari presentation remain behind injected/app-owned action seams.
5. Deep links enter through `AppDeepLinkParser` and `ShellStore`; do not add a second URL parser to `AppRouter`.
6. Active-wallet library behavior stays scoped. Any cross-wallet creator behavior must be named, tested, and visually documented as an intentional exception.
7. Shared URLs must not contain analytics, tracking parameters, API keys, wallet secrets, or provider internals.
8. Missing local content is a normal outcome for shared links and must render friendly empty states.

## Ticket Summary

| ID | Title | Type | Priority | Estimate | Depends |
| --- | --- | --- | --- | --- | --- |
| P12-001 | NFT provenance panel using current AuraPlay media metadata | TASK | P1 | 2 hrs | P9 Library, P10 context actions, current `AuraPlayExplorerURLBuilder` |
| P12-002 | Share policy for media, collections, and playlists | TASK | P1 | 1.5 hrs | P12-001, P9 playlists/details, P10 context actions |
| P12-003 | Creator profile view with explicit cross-wallet aggregation | TASK | P1 | 2.5 hrs | P9 creator grouping, current `AuraPlayMediaItemService` |
| P12-004 | AuraPlay deep-link routing and ADR-007 custom-scheme decision | TASK | P1 | 2 hrs | Existing `AppDeepLinkParser`, `ShellStore`, `AppRouter`, P12-002, P12-003 |

## P12-001 — NFT provenance panel using current AuraPlay media metadata

Priority: P1  
Estimate: 2 hrs

### Description

Add a provenance sheet for playable media that shows the on-chain facts AuraPlay already persists: chain, contract address, token ID, token type, collection, and explorer destination. This reinforces that AuraPlay is a transparent read-only viewer.

### Technical Notes

- Add package-owned presentation types in `MusicFeature`, for example `AuraPlayProvenancePresentation` and `ProvenancePanelView`, built from `MediaItemQueryItem` and player presentation data where available.
- Use real field names: `chain`, `contractAddress`, `tokenID`, `tokenType` / `tokenTypeDisplayName`, `collectionName`, and `sourceNFTID`.
- Display `chain.routingDisplayName`, not the raw chain id.
- Treat `tokenType` as provider metadata. Do not force it into only ERC-721/1155/Metaplex labels unless the source value proves that standard.
- Keep explorer construction in the app target through `AuraPlayExplorerURLBuilder`. If `MusicFeature` needs URL data, inject it as a tiny policy/closure rather than importing `ExplorerAdapter` into UI code.
- Surface the panel from the shared context menu path (`AuraPlayPlayerContextMenuBuilder`) and, where appropriate, an info button in `AuraPlayPlayerView`.
- Copy-to-pasteboard uses the existing context-action handler. Add a haptic/toast through the app or AuraUI feedback path already used for `playerCopyToast`; do not let the package write directly to `UIPasteboard`.

### Acceptance Criteria

- Provenance panel displays correct chain name, full contract address, token ID, token type, and collection for fixture `MediaItemQueryItem` values.
- EVM explorer URL construction is verified through `AuraPlayExplorerURLBuilder` / `ExplorerAdapter`; Solana uses the existing Solscan policy.
- Missing contract/token values degrade gracefully and do not show broken links.
- Copying a contract writes the full non-truncated address and shows the existing copy confirmation behavior.
- Code/content audit finds no price, listing, offer, marketplace, or transaction-history fields in the panel.

## P12-002 — Share policy for media, collections, and playlists

Priority: P1  
Estimate: 1.5 hrs

### Description

Formalize what AuraPlay shares from item, collection, and playlist surfaces. Media shares should prefer public explorer URLs. Local AuraPlay objects that have no public chain representation should use app deep links plus plain text context.

### Technical Notes

- Keep using the current app-owned `AuraPlayPlayerContextActionHandler` / UIKit `UIActivityViewController` path for live iOS sharing. `ShareLink` is acceptable only where it reduces code and still fits the existing action seam.
- Media item shares use the explorer URL returned by `AuraPlayExplorerURLBuilder` and a short text description built from title, creator, collection, and chain.
- Collection shares use an internal AuraPlay deep link containing enough durable payload to find local content: chain plus contract address when present, falling back to normalized collection key only for local same-device links.
- Playlist shares use local `AuraPlayPlaylist.id`. This is intentionally device-local for v1 because playlists are SwiftData-only and are not synced across devices.
- Add a small URL builder, for example `AuraPlayDeepLinkBuilder`, near routing code or app-owned AuraPlay integration code. Do not scatter string interpolation through views.
- Generated URLs must contain no analytics or tracking parameters.

### Acceptance Criteria

- Media sharing produces the expected explorer URL and description text.
- Playlist sharing produces `auraplay://playlist/{id}` plus description text.
- Collection sharing produces a well-formed custom-scheme link with chain and contract when available.
- Shared URLs contain no `utm_*`, analytics, provider, API-key, wallet-secret, or session parameters.
- Player and library share actions use the same URL/text policy.

## P12-003 — Creator profile view with explicit cross-wallet aggregation

Priority: P1  
Estimate: 2.5 hrs

### Description

Expand creator grouping into a creator profile that can aggregate a creator's media across connected wallets. This must be implemented as an explicit exception to the usual active-wallet library scope, not as accidental leakage from global queries.

### Technical Notes

- Current `LibraryGroupDetailLoaderView` / `LibraryGroupDetailView` is active-scope based. Keep that behavior for normal Library navigation unless this ticket deliberately introduces a new creator route.
- Add a named query contract such as `fetchCreatorProfile(creatorIdentifier:across accounts:[String], chains:Set<Chain>?)` or an explicit `AuraPlayCreatorProfileQuerying` protocol. Do not overload `AuraPlayLibraryScope` with ambiguous nil account behavior.
- Use connected accounts from the app shell/account store, not arbitrary wallet input.
- Merge by `creatorIdentifierRawValue` where available. Fall back to `normalizedArtistKey` only for existing rows that lack a creator identifier, and document duplicate-display-name behavior.
- Header stats should include item count and chain badges. Listening stats should use `lastPlayedAt`/playback-position state that already exists; do not invent a new analytics table for this phase.
- The grid/list below the header should reuse `LibraryItemCell` / `LibraryItemCellViewModel` or the existing detail row components. Do not create a third media card design.
- Items do not need wallet-source badges in v1, but tests must prove the underlying query is cross-wallet.

### Acceptance Criteria

- Fixture data with the same creator across two connected accounts aggregates into one creator profile.
- Header item count and chain badges reflect the full cross-wallet result set.
- Playback/listening stats sum only local AuraPlay playback state and handle missing state as zero.
- Switching the active wallet after opening the creator profile does not shrink the profile to the newly active wallet.
- Duplicate artist display names with different `creatorIdentifierRawValue` values remain separate creator profiles.

## P12-004 — AuraPlay deep-link routing and ADR-007 custom-scheme decision

Priority: P1  
Estimate: 2 hrs

### Description

Extend the existing Auralis deep-link stack to understand AuraPlay destinations and record the link mechanism decision in ADR-007. The primary v1 mechanism is the already-declared `auraplay` custom URL scheme. HTTPS universal links remain deferred unless the team commits to hosting a real `apple-app-site-association` file on a controlled domain.

### Technical Notes

- Record ADR-007 in `Auralis/Auralis/docs/decisions/ADR-007-auraplay-linking.md`.
- Extend `AppDeepLinkDestination` with AuraPlay cases such as playlist, music collection, and creator. Keep the cases shell-level and domain-shaped; avoid view-type names.
- Extend `AppDeepLinkParser` for `auraplay://playlist/{id}`, `auraplay://collection/{contract}`, and `auraplay://creator/{identifier}`. Include chain query values where collection routing requires chain disambiguation.
- Route through `ShellStore.send(.deepLinkReceived)` and existing shell routing effects. Add router methods/routes as needed, such as `MusicRoute.playlist(id:)` and `MusicRoute.creator(id:title:)`.
- Do not add `AppRouter.handle(url:)`; that is not the current architecture.
- Not-found states belong in MusicFeature presentation loaders: missing playlist shows "This playlist isn't available on this device"; missing collection/creator shows a local-library empty state.
- Malformed/unrecognized URLs should be logged and ignored or routed to the existing shell route-error path according to current parser conventions. Keep user-visible errors for links that parse but cannot resolve local content.

### Acceptance Criteria

- ADR-007 records custom-scheme-only for v1 unless a real hosted AASA deployment is chosen.
- `auraplay://` links for playlist, collection, and creator parse through `AppDeepLinkParser` and route through `ShellStore` into the Music tab.
- A collection link for owned local content opens the correct AuraPlay collection detail.
- A collection or creator link with no local matches shows a friendly empty state, not a blank screen or crash.
- A playlist link for a missing local playlist shows "This playlist isn't available on this device."
- The P12-002 share builder output is fed back into the parser in tests and routes to the expected destination.
- HTTPS universal links are either verified on device with a real controlled-domain AASA file or explicitly documented as deferred in ADR-007.

## Explicit Non-Goals

- No NFT sales, marketplace, pricing, offers, floor prices, listings, trading, or transaction-history UI.
- No backend service, hosted playlist pages, or server-side preview generation.
- No cross-device playlist sync.
- No wallet-source badges on creator profile items in v1.
- No global app search replacement; AuraPlay creator/collection links route inside the Music tab.
- No new provider fetch just to resolve shared links. Shared links resolve against local AuraPlay persistence.

## Recommended Implementation Order

1. Write ADR-007 and add URL builder/parser tests for the custom-scheme decision.
2. Add provenance presentation and explorer/copy tests around current metadata.
3. Consolidate share URL/text policy and reuse it from player/library surfaces.
4. Add route cases and not-found MusicFeature loaders.
5. Add explicit cross-wallet creator query/profile support and tests.

## Test Plan

- Swift Testing for URL builders, parser cases, share policy, provenance presentation mapping, and creator aggregation query behavior.
- Existing app-hosted `AuralisTests` for shell routing effects and app-target explorer URL construction.
- UI/snapshot coverage only where presentation changes are meaningful: provenance sheet, creator profile empty state, and missing playlist link state.
- No network fetches in tests. Explorer validation is URL construction only.
