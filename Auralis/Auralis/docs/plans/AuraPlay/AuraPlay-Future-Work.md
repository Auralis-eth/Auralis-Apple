# AuraPlay Future Work

AuraPlay Phase 1 built the stage, not the full show. This file tracks the work that is still intentionally incomplete after the module-foundation pass.

## Priority Order

1. Migrate one user-facing music surface at a time into AuraPlay.
2. Prove playback and queue lifecycle behavior on physical devices before broadening scope.
3. Deepen test execution confidence so the module is not relying on build-only validation.
4. Remove the legacy `AI/V1` path only after parity is real, not aspirational.

## Highest-Value Incomplete Work

### 1. Move the Library surface onto the AuraPlay presentation stack

Why it matters:

- the current AuraPlay root is still a foundation shell, not the real music library experience
- Library is the lowest-risk migration slice because it is mostly read-heavy

Success looks like:

- the Music tab’s primary browse surface renders through AuraPlay presentation code
- library items use injected repository, artwork, logging, and error seams
- legacy `NFTMusicPlayerLibraryView` stops being the main browse dependency

### 2. Migrate collection and detail flows

Why it matters:

- the module boundary is only proven once more than the root summary screen can use it
- collection/detail work exercises scope propagation, routing, artwork, and availability presentation

Success looks like:

- collection and item detail screens live under `Auralis/MusicApp/AuraPlay/Presentation/`
- routing remains shell-owned and does not fork into a second router

### 3. Migrate Now Playing and queue orchestration last

Why it matters:

- this is the sharpest lifecycle surface in the music stack
- backgrounding, interruption handling, stale loads, and queue ownership all converge here

Success looks like:

- Now Playing uses injected playback and queue seams rather than directly interrogating legacy view internals
- mini player and full player share one coherent playback model
- the queue contract is explicit enough to test without the live engine

### 4. Strengthen the queue seam beyond count snapshots

Current posture:

- Phase 1 only proves queue visibility through a lightweight snapshot

Next move:

- promote the queue seam into a richer contract that can expose ordered upcoming/history items, active context, and mutation intents

### 5. Decide whether `AudioEngine` itself needs deeper decomposition

Why it matters:

- the shared engine still owns download transport, temp-file lifecycle, playback session control, queue state, and presentation-facing state
- AuraPlay now has seams around it, but the engine remains a dense concrete type

Likely follow-on:

- split transport, file lifecycle, queue coordination, and playback-session responsibilities into clearer units if Phase 2 work starts straining the adapter layer

## Validation Gaps Still Open

### Physical-device execution

- Phase 1 builds are green, but real-device playback validation still needs a deliberate pass
- interruption handling, route changes, background behavior, and rapid track swaps are not the kind of thing to trust to simulator folklore

### Test execution environment

- the new AuraPlay test seams compile, but focused test execution in the current session environment reported `No result`
- before calling the rebuild deeply hardened, confirm those tests execute successfully in a working simulator or CI environment

### Performance and polish

- the AuraPlay root is intentionally skeletal
- real performance, visual hierarchy, and interaction quality still depend on the first migrated user-facing surfaces

## Things To Resist

- do not migrate Now Playing before Library and detail flows have proven the architecture
- do not let leaf views talk straight to `AudioEngine` because it is convenient
- do not create a second navigation store inside AuraPlay
- do not remove `AI/V1` code just because the new root compiles

## Suggested Next Sprint

1. Build the AuraPlay Library screen on top of the repository and artwork seams.
2. Run the AuraPlay physical-device suite on a real iPhone.
3. Confirm the new AuraPlay tests execute in CI or a healthy local simulator environment.
4. Start the collection/detail migration only after Library is credible.
