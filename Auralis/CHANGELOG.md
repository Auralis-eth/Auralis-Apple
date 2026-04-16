# Changelog

## Unreleased

### Shipped
- Aura shell flow with gateway, loading, and main tab routing.
- Wallet-scoped NFT refresh and SwiftData persistence.
- Home, News Feed, Gas, Music, Search, Receipts, and Settings surfaces.
- Guest pass onboarding, account switching, and chain-scoped browsing.
- Deep-link parsing and routed error presentation.
- Shared audio engine with mini-player and music detail flows.

### Notable Fixes
- Added provider-failure presentation paths so cached NFT content can remain visible during degraded refresh states.
- Hardened shell routing around pending deep links, account switches, and route reset behavior.
- Added broader unit coverage across router, search, receipts, shell logic, provider boundaries, and URL helpers.

### Known Limitations
- Some tabs and feature areas are still scaffold-level and not equally mature.
- Receipt routing is intentionally safe-fail; full receipt support is still incomplete.
- Legacy music code remains in `Auralis/Auralis/MusicApp/OLD/` and should not be treated as active without verification.
- Some oversized files, especially `Auralis/Auralis/DataModels/NFT.swift`, still carry too many responsibilities.

### Deferred Nice-to-Haves
- Break up oversized model and shell files into narrower responsibilities.
- Expand placeholder surfaces into fully productized flows.
- Add broader manual QA and release hardening coverage for physical-device edge cases.
- Continue follow-on architecture cleanup for persistence, routing, and library presentation boundaries.
