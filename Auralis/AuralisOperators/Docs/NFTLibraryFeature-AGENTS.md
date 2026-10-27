# NFTLibraryFeature Project Memory

## Project Overview

NFTLibraryFeature is the Swift package boundary for Auralis NFT browsing surfaces. It owns route and sort domain values, presentation helpers, image loading, cards, collection detail, detail screens, loading and status views, and the small service dependency surface used by the app target.

## Architecture Decisions

- Keep this package UI-focused and dependency-light: domain routing, presentation mapping, and reusable SwiftUI views live here.
- Use `AuralisPrimaryModels` for shared NFT and chain models instead of duplicating app-domain structures.
- Use `NFTKit` provider failure presentation for user-facing refresh and provider error states.
- Keep navigation payloads as model ids so callers can route back into the app shell consistently.
- Keep network image loading local to `NFTImageLoader`, with a reusable `URLSession`, cache, retry-aware errors, response validation, payload-size limits, and downsampling.

## Important Conventions

- SwiftUI-first, state-driven views.
- Prefer presentation helpers for display fallback and filtering rules instead of scattering formatting in views.
- Preserve scoped NFT ids when opening item detail; fixture ids may be rewritten by `NFT.applyRefreshScope`.
- Use Swift Testing for unit tests.
- Prefer targeted changes that keep this feature package isolated from live app infrastructure.

## Build And Run

- Use the `NFTLibraryFeature` scheme in Xcode.
- Build with Xcode or the MCP `BuildProject` tool.
- Run focused tests with the active test plan when changing presentation helpers or image loading.

## Quirks And Gotchas

- `NFT` ids are not necessarily the literal ids passed into test factories; initialization scopes ids by account, chain, contract, and token.
- Contract identity can appear on both `NFT.contract.address` and `NFT.collection.contractAddress`; collection filtering should tolerate both shapes.
- The image loader must reject video responses by MIME type, not only by URL extension, because many NFT media URLs are extensionless.
- `NFTCachedAsyncImage` is UIKit-gated because it caches and renders `UIImage` instances.
