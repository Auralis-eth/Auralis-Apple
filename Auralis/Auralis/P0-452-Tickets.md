# P0-452 Tickets And Session Handoff

## Summary

Implement the first music collection and item detail screens on top of the `P0-451` library/index foundation.

## Ticket Status

Startable.

## Execution Checklist

### 1. Confirm detail routing and data inputs

- [x] Re-read `P0-452-Strategy.md` and `P0-452-Dependency-Note.md`.
- [x] Confirm how Music library rows route into item detail.
- [x] Confirm which source `NFT` and library-index fields belong on item vs collection detail.

Step 1 notes:

- Music library rows already have a real item-detail route: `NFTMusicPlayerLibraryView` resolves the source `NFT`, then calls `onOpenNFT(nft)`, which the Music tab currently wires to `router.showMusicNFTDetail(id:)`.
- The current Music item detail destination is the tab-scoped `NavigationStack(path: $router.musicPath)` in `MainTabView`, which presents `SharedNFTDetailView` for `NFTDetailRoute`.
- `MusicLibraryItem` is the right browse/index source for scoped list and collection-grouping fields such as `title`, `artistName`, `collectionName`, `artworkURLString`, `playbackURLString`, `availability`, and scope/index timestamps.
- `NFT` remains the canonical richer item-detail source for the actual NFT identity and media metadata such as `name`, `nftDescription`, `contentType`, `collectionName`, `artistName`, `animationUrl`, and `audioUrl`.
- Product decision confirmed with user: Music detail navigation must read as one navigation system to the user. Do not introduce nested or parallel detail navigation that creates double back arrows or stacked back affordances.
- Implementation consequence: collection detail should stay inside the mounted Music navigation experience and must not add a second visible navigation layer.

### 2. Implement item detail

- [x] Add the first music item detail screen.
- [x] Show the essential track, collection, and artwork metadata.
- [x] Keep the screen honest when playback or metadata is partial.

Step 2 notes:

- The Music tab now uses a dedicated `MusicItemDetailView` instead of falling through to the generic shared NFT detail used by News and NFT Tokens.
- The route stays on the existing Music tab `NavigationStack`, so the visible navigation model remains one stack with one back affordance.
- The item-detail presentation uses `NFT` as the canonical source for richer identity and descriptive metadata, while `MusicLibraryItem` supplies indexed browse/playback fields such as artist, collection, artwork URL, and availability.
- The screen stays useful when data is partial by falling back from `NFT` to indexed music metadata and by showing explicit playback/metadata status instead of silently pretending the item is fully resolved.

### 3. Implement collection detail

- [x] Add the first grouped collection detail screen.
- [x] Reuse the established routing and library contracts.
- [x] Keep the collection screen distinct from full playlist or curation work.

Step 3 notes:

- The Music tab now has a dedicated `MusicRoute` stack with `item` and `collection` routes, so collection detail and item detail share the same visible navigation system.
- `NFTMusicPlayerLibraryView` now exposes grouped collection entry points from `MusicLibraryItem` data instead of inventing a second collection store.
- `MusicCollectionDetailView` is a browse-only collection screen: it summarizes the collection, lists scoped local tracks, and lets the user drill from collection detail into item detail on the same Music stack.
- The collection contract stays intentionally narrow: it groups local music-library items by normalized collection key and does not drift into playlist editing, curation flows, or playback-engine behavior.

### 4. Validate the vertical slice

- [x] Verify detail screens open from the mounted Music surface.
- [x] Verify partial metadata does not break item or collection detail.
- [x] Record any deeper playback/capture work outside this ticket.

Step 4 notes:

- Validation completed with the mounted Music stack, not a separate ad hoc preview path.
- `Auralis` builds successfully with the dedicated Music item and collection detail work in place.
- Focused tests passed for:
  - `AppRouterTests/musicDetailFlow()`
  - `MusicItemDetailPresentationTests/presentationUsesCanonicalNFTAndIndexedPlaybackFields()`
  - `MusicItemDetailPresentationTests/presentationDegradesCleanlyForSparseMetadata()`
  - `MusicItemDetailPresentationTests/presentationFallsBackToIndexedMetadataWhenNFTIsMissing()`
  - `MusicCollectionPresentationTests/summariesGroupItemsByCollection()`
  - `MusicCollectionPresentationTests/summariesFallbackWhenCollectionNameIsMissing()`
  - `MusicCollectionPresentationTests/detailPresentationReportsSparseMetadata()`
- Deeper playback and capture work remains outside this ticket: richer collection playback controls, queue/cueing behavior from collection detail, and any capture/provenance-specific affordances belong in later tickets instead of stretching `P0-452`.

## Ticket Status

Completed for the current slice.

## Critical Edge Case

Music detail screens must remain useful when metadata is partial and must not silently fall back to unrelated raw-NFT view logic.

## Validation

Open item and collection detail from Music, preserve graceful partial-metadata handling, and keep the screens scoped to browsing/detail work.

## Handoff Rule

If a requested enhancement is really about playback engine depth or playlist behavior, split it into later tickets instead of stretching `P0-452`.
