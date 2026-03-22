# Aura Primitives

This folder is the home for shared Aura-level UI primitives introduced by `P0-101E`.

Rules:

- keep primitives close to the product UI layer
- prefer narrow, composable building blocks over feature-specific mega-components
- preserve the existing Aura language from Gateway, Home, and Gas
- do not move generic helpers here unless they are directly part of the UI primitive API

Expected first slice:

- `AuraScenicScreen`
- `AuraSurfaceCard`
- `AuraSectionHeader`
- `AuraActionButton`
- `AuraPill`
- `AuraEmptyState`
- `AuraErrorBanner`
