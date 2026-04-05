# Journal

## The Big Picture

Auralis is what happens when an NFT wallet viewer, a chain-aware dashboard, a receipt timeline, and a music app decide to share one apartment. You bring an address, Auralis restores your scope, fetches and persists the collection, and then lets multiple product surfaces work off that same identity without pretending they live in separate universes.

## Architecture Deep Dive

The app shell is the front desk. `MainAuraView` and `MainTabView` decide who is checked in, which chain they are standing on, and which wing of the building they should be sent to next.

`AccountStore` is the guest book. It normalizes addresses, prevents duplicates, and records account-level actions so the app can explain what happened later.

`NFTService` is the loading dock. It pulls inventory from the network, deals with retries and throttling, then hands clean data to SwiftData for local persistence.

`ContextService` is the concierge clipboard. It gathers current account, chain, freshness, receipt count, and native balance into one snapshot so the chrome and shell UI can speak with one voice instead of improvising conflicting stories.

The receipt system is the black box recorder. When something important happens, the app writes down enough scope and payload detail to reconstruct the story later without forcing every feature to invent its own logging language.

## The Codebase Map

`Auralis/Auralis/Aura/` is the visible product shell: auth, tabs, home, news, search, and shared chrome.

`Auralis/Auralis/Accounts/` holds account persistence and account event recording.

`Auralis/Auralis/Networking/` contains provider seams, NFT refresh orchestration, throttling, and chain-backed reads.

`Auralis/Auralis/Receipts/` is where timeline storage, filtering, and event logging live.

`Auralis/Auralis/MusicApp/AI/` is the active music path. `OLD/` is the attic. Do not assume the attic is load-bearing.

`Auralis/Auralis/DataModels/` is the durable model layer, including `EOAccount`, `NFT`, chain types, and receipt storage models.

## Tech Stack & Why

SwiftUI drives the UI because the app is mostly state choreography: account scope, chain scope, loading state, navigation state, and media state all need to stay in sync without UIKit glue code metastasizing everywhere.

SwiftData handles local persistence because the app wants durable local state for accounts, NFTs, and receipts without building a custom database layer for every feature.

Swift Concurrency is the right fit because network reads, refresh flows, and snapshot building are naturally async tasks, and the codebase already prefers explicit async seams over callback soup.

Receipt-backed event logging exists because this app has a lot of long-lived state. When something feels wrong, “what happened?” is not a philosophical question, it is a product requirement.

## The Journey

### War story: P0-461 started with a route that already existed, but no surface

The first pass through the token-holdings ticket could have gone sideways fast if we had treated “add holdings” like “invent a new token area.” The seam was already there: `ERC20TokensRootView` existed, but it was a polite cardboard sign saying the portfolio surface was not built yet.

The useful discovery was that native balance does not need a new provider abstraction. The app already has one. `ContextService` asks the injected `NativeBalanceProviding` seam for a scope-aware balance and folds it into the shared snapshot. That means the first vertical slice can stay honest: show native balance now, keep ERC-20 rows pluggable later, and avoid building a second balance pipeline that would need to be deleted in a week.

Another important product decision is now explicit: token holdings are expected to be persisted with SwiftData. In other words, the token list should behave more like the app's other durable libraries and less like a temporary network overlay that vanishes the moment a request fails. That matters because “show me what I own” is exactly the kind of feature users notice when it forgets yesterday.

### War story: the first ERC-20 screen is really a persistence exercise disguised as a list

The visible change is an ERC-20 tab that finally shows something useful. The real engineering move is underneath: the new `TokenHolding` model gives Auralis a durable shelf for token balances scoped by account and chain. The first row is the native asset, persisted from the shared shell context snapshot. That sounds modest, but it solves the important failure mode: when the latest provider-backed read does not arrive, the app can still show the last known holdings state instead of shrugging and pretending the wallet is empty.

This is one of those cases where “just render the balance directly” would have been the cheap version and the wrong version. The app already learned that long-lived wallet state needs receipts, scope, and local durability. Token holdings belong in that family too.

### Aha: edge cases got cheaper once the row contract stopped caring where the data came from

Three ugly cases became much easier once the holdings screen was built around a stable row model instead of a direct provider response:

- native-only wallets work because the native row is already a first-class persisted holding, not a special header pretending not to be part of the list
- missing ERC-20 metadata is survivable because the row can render placeholders without assuming symbol or contract detail is present
- scope leaks are easier to catch because the persistence ID and query both speak the same language: normalized account plus chain

That is a useful engineering pattern in this app. If the screen contract is stable before enrichment arrives, partial data feels like an honest early slice. If the screen contract depends on fully enriched payloads, every missing field turns into drama.

### Follow-up still on the board: the app needs a real token-holdings provider call

P0-461 closed the “empty room” problem for the ERC-20 tab, but it did not magically solve ERC-20 discovery. Right now the durable storage shape and UI contract exist, and native balance is persisted into that shape. The missing ingredient is a provider-backed API call that returns token holdings for an account so Auralis can populate real ERC-20 rows.

That follow-up matters because this is exactly where teams accidentally lie to themselves. Once the screen exists, it is easy to start speaking as if “token holdings” are done. They are not. The native-balance-first slice is done. Full account token inventory still needs a network seam, persistence mapping into `TokenHolding`, and the usual scope/freshness/receipt discipline.

### Home learned the difference between "empty" and "broken"

`P0-102E` put an important line back into the product: Home now distinguishes sparse local data from onboarding, loading, and failure states. That sounds obvious until you look at how many apps quietly blur those together and make users guess whether they should wait, retry, or leave.

The key design choice was not to build a separate empty-screen universe. The Home shell stays mounted. Identity, modules, quick links, and the scenic background all remain in place, and a dedicated sparse-state card explains what is actually missing. That makes the dashboard feel honest instead of abandoned, and it avoids the common trap where empty-state work becomes a parallel design that later fights the real populated layout.

The useful engineering move here was making sparse-state presentation a tiny contract instead of letting it leak through the view as scattered `if` statements. Once loading, failure suppression, and allowed actions were written down in one place, the edge cases stopped being vibes and started being test cases.

### The summary card finally started acting like it knew who the user was

`P0-102B` took the Home identity card out of the decorative-placeholder zone. The card now uses real shell-owned facts: account name, scoped address, active chain, scoped NFT count, and recent account activity when available. That sounds basic, but this is exactly the difference between a card that merely looks premium and a card that actually earns its space.

The good constraint here was refusing to cram in every shiny field. No fake portfolio math, no profile-settings sprawl, no “we’ll backfill it later” mystery metrics. Just a tighter identity-and-scope summary built from values the shell already owns and can defend.

### Tiny bug, useful lesson: a missing `Foundation` import can masquerade as a flaky test runner

While tightening `P0-102B` edge-case coverage, the focused Swift Testing run kept reporting `No result`, which is the kind of message that makes you suspect Xcode gremlins. The real culprit was much less glamorous: `HomeTabLogicTests.swift` used `Date` but did not import `Foundation`, so the test build failed before execution and the runner surfaced the failure in a very unhelpful way.

That is a good reminder that “the test runner is weird” is often only half the story. When a targeted run looks flaky, check the generated build log before blaming discovery. In this case, the right fix was boring and correct: add the import, rerun the focused tests, and move on.

### Aha: view logic got easier to trust once the summary card had a pure contract

The best change in the `P0-102B` edge-case pass was not visual. It was introducing a small `HomeAccountSummaryPresentation` contract fed by plain inputs. That turned the summary card from “a SwiftUI view with some conditional text” into “a deterministic formatter the view renders.”

Once the logic was written down that way, the edge cases stopped being hand-wavy:

- missing account metadata has a named fallback
- chain changes visibly alter scope text
- no activity data means no activity label, not a suspicious fake timestamp

This is one of those senior-engineer habits worth stealing. If a view has important product truth inside it, give that truth a small shape that tests can grab directly.

### Unit-test-only validation can still tell a coherent product story

For the `P0-102B` validation pass, the constraint was explicit: no UI tests. That could have turned into hand-waving, but it did not need to. The summary card already sat on top of pure formatting logic, and Home sparse-state behavior already lived in its own small contract, so a full Home logic suite was enough to validate the slice honestly.

That suite proved three things that matter:

- the card tracks real account and chain scope
- sparse Home logic still behaves correctly around it
- optional or missing richer context does not make the identity surface collapse into nonsense

The subtle lesson is that a vertical slice gets much easier to validate without UI automation when the product truth is not trapped inside view rendering. If the important behavior can be described as “given these inputs, the shell should say this,” unit tests can carry a surprising amount of weight.

### The next Home trap: not every button-shaped thing is a module

Starting `P0-102C` exposed a subtle Home taxonomy problem. The dashboard already had a `modulesSection`, a `quickLinksSection`, and a `Profile Studio` area. All three contain actions. Only one of them should become the intentional launcher layer.

That matters because if we start treating every useful button as a “module,” the Home screen turns into a junk drawer with nice lighting. The clean read is:

- modules are durable product surfaces such as Music and NFT Tokens
- quick links are lightweight shell jumps like Search, News, and Receipts
- profile studio is temporary local tooling and should not pretend to be part of the launcher taxonomy

This is mostly product language, but it becomes architecture very quickly. Once the taxonomy is clear, `P0-102C` can deepen the module layer without quietly swallowing unrelated Home controls.

### The launcher got better once Home admitted it had two different kinds of shortcuts

The useful move in `P0-102C` was not “add more buttons.” It was admitting that Home has two layers of navigation:

- primary modules for durable product surfaces
- lighter shell shortcuts for fast jumps into adjacent tabs

Once that was explicit, the old split between `modulesSection` and `quickLinksSection` stopped making sense. The launcher now lives in one place, but it still has internal hierarchy: Music and NFT Tokens are the primary cards, while Search, News Feed, and Receipts sit underneath as shell shortcuts.

That is the kind of small structural cleanup that makes later work cheaper. `P0-102D` can now sit next to a launcher that already knows what it is, instead of next to a dashboard that accidentally grew two competing shortcut systems.

### A good launcher can be defined by what it refuses to include

The `P0-102C` edge-case pass reinforced a simple rule: one way to keep a launcher honest is to prove what is not in it. The Home launcher now advertises only routes that are already real in the shell: Music, NFT Tokens, Search, News Feed, and Receipts.

That sounds almost trivial, but it saves a lot of product debt. The moment a launcher starts listing “future” destinations, users stop trusting the difference between a real module and a dressed-up placeholder. In Auralis, the clean approach is to make unsupported ideas absent, not dimmed, not vague, not “coming soon” in disguise.

That gives the team a useful planning lever too. If a future module wants launcher space, it should earn it by becoming a real destination first.

### Launcher validation worked because the routing contract was written down before the visuals drifted

The nice thing about the `P0-102C` validation pass is that it did not need UI automation to say anything useful. Once the launcher had a real `HomeLauncherAction` contract and a `HomeModulesPresentation`, the important questions became testable:

- which destinations are exposed
- what order they appear in
- whether sparse data changes the launcher surface
- whether any fake or future routes sneak in

That is a good pattern for Home work in general. If the product intent can survive being expressed as a small data contract, the tests can protect it long before screenshots or UI tests enter the conversation.

### The recent-activity preview already had a trustworthy source, which is half the battle

Starting `P0-102D` surfaced a reassuring detail: Home does not need to invent a new activity model. The data is already there. `StoredReceipt` is the durable event log, `ReceiptTimelineRecord` is the readable projection, and `ReceiptTimelineScope` already knows how to filter that history down to the active account-and-chain slice.

That is exactly the kind of seam you want before touching UI copy or row polish. It means the preview can stay lightweight without becoming fake. Home is not summarizing “activity-ish vibes.” It is summarizing the same scoped receipts that the deeper receipts surface already trusts.

### Home activity got better once the preview stopped pretending it was a tiny timeline

The first useful implementation move in `P0-102D` was shrinking the ambition, not expanding it. The Home card no longer tries to be a miniature copy of the receipts screen. Instead, it builds a small preview contract with just enough information to answer the question “what just happened here?” without dragging timeline-level density onto the dashboard.

That meant three concrete choices:

- keep only a few rows in Home
- give each row a clear title plus lighter supporting context
- preserve the receipts routes for anyone who wants the full story

That is a good Home pattern in general. A dashboard preview should be a headline, not a backlog.

### Recent-activity validation worked because the preview logic had a shape of its own

The clean part of the `P0-102D` validation pass is that it never needed to argue about pixels. Once the preview became its own small contract, the meaningful questions were straightforward:

- does empty history stay empty
- does partial receipt data still yield readable rows
- does Home stay shorter than the real timeline

That is exactly the right level of certainty for a Home preview. The receipts screen still owns depth. Home now owns a compact, testable summary of the same truth.

### Gotcha: freshness is a shell concern, not a token-screen side quest

It is tempting to let a new holdings screen invent its own “last updated” badge. That would be wrong here. Freshness already lives in the shared context snapshot, and `ReceiptEventLogger` already records context builds with scope metadata. If the holdings surface starts freelancing its own freshness story, the user will eventually see two timestamps arguing in public.

## Engineer's Wisdom

Good seams are usually already present in a mature codebase, just under less glamorous names. Before adding a new service, check whether the existing snapshot builder, router, or receipt system is already carrying the exact contract you need.

Stable row models matter. If v0 native balance and v1 ERC-20 enrichment cannot share the same list contract, the first version was not a vertical slice, it was a throwaway prototype wearing production clothes.

Scope is everything in a wallet app. If account and chain are not attached at the seam, bugs will leak data across contexts and make the UI look haunted.

## If I Were Starting Over...

I would split oversized files like `NFT.swift` earlier. Giant “miscellaneous but important” files are where clarity goes to get lost.

I would also make the token-holdings surface explicit sooner in the shell instead of leaving a placeholder root view in place. A placeholder is fine for a sprint, but after that it becomes camouflage: the route exists, so everyone assumes the feature is somehow more real than it is.
