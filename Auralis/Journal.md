# Journal

## The Big Picture

Auralis is what happens when a wallet viewer, an NFT browser, a receipts ledger, and a music player all decide to share one cockpit instead of yelling across the room. The app lets you point at a wallet, pull in scoped on-chain inventory, keep a local snapshot in SwiftData, and move around the shell without pretending every provider call is always fresh and perfect.

## Architecture Deep Dive

The shell is the front desk. `MainAuraView` decides whether you are still in the lobby, loading inventory, or already inside the app. `MainTabView` is the hallway that branches into Home, News, Gas, Music, Receipts, Search, NFT Tokens, and ERC-20 Tokens.

The provider layer is the kitchen. `ReadOnlyProviderFactory` hands out the right Alchemy or Infura tools without every feature building its own spoon. `ContextService` is the expediter: it pulls live scope data together, stamps freshness and provenance onto it, and sends a clean plate to the chrome and inspector.

SwiftData is the pantry. `NFT`, `TokenHolding`, playlists, receipts, and account rows live there so the app can keep showing something useful when the network flakes out instead of acting like it has never met the user before.

## The Codebase Map

`Auralis/Auralis/Aura/`
This is the shell and feature UI layer. If you are looking for tabs, routes, chrome, empty states, or the ERC-20 holdings screen, start here.

`Auralis/Auralis/Networking/`
This is the provider seam. The important rule is simple: extend the existing provider stack before creating another network path just because a new ticket showed up.

`Auralis/Auralis/Accounts/`
This is where account and token-holdings persistence logic lives. If a scoped holdings row needs to be saved, reconciled, or deleted, this folder is where the knives are.

`Auralis/AuralisTests/`
This is the guardrail layer. A lot of the value here is contract coverage: route behavior, provider seams, scoped persistence, and presentation honesty.

## Tech Stack & Why

SwiftUI because the app is heavily state-shaped and the shell needs to react to changing scope, freshness, and provider state without hand-rolling view controllers for every corner.

SwiftData because scoped local persistence is not optional here. Wallet inventory and receipts need to survive provider hiccups, app relaunches, and feature handoffs.

Async/await because the app is constantly juggling fetches, refreshes, and cancellation. Callback soup would turn this codebase into a haunted house fast.

Alchemy plus Infura because the product already depends on real provider-backed blockchain reads, and the clean move is to centralize those seams instead of scattering endpoint knowledge through views.

## The Journey

### War Story: P0-461 grew up

The original `P0-461` landing was honest but incomplete: the ERC-20 tab was a real SwiftData surface, but it was basically native balance plus empty promises. The missing piece was live ERC-20 inventory.

The trap would have been easy: bolt a one-off `fetch()` into the view, decode a new shape there, and call it “done.” That would have created a second provider path and immediately aged badly.

The actual fix was to extend the existing read-only provider layer with the Alchemy Data API, then reconcile those rows into `TokenHolding` through `TokenHoldingsStore`. Same persistence model. Same scope rules. Same cached-state behavior. No side quest architecture.

### Aha Moment

The right place to “finish ERC-20 holdings” was not the detail screen and not the router. The hole was lower: the app already had a stable row contract and a mounted tab. What it lacked was a trustworthy sync seam underneath that surface.

### Pitfall

Provider-backed success should not mean “delete everything and hope the next call works.” The holdings reconciliation path only replaces ERC-20 rows after a successful scoped fetch. If the provider fails, the cached rows stay on screen and the UI admits it is showing last saved data.

### War Story: Decimal math will happily lie if you let it

There was a sneaky failure mode in the ERC-20 fallback path. `balances/by-address` gives you the raw integer balance, but not the token decimals. If enrichment from `tokens/by-address` failed, the app could still have a real balance like `1000000` and no idea whether that meant `1.0`, `0.001`, or something else entirely.

The dangerous version of this bug is not a crash. It is confidence. The UI can calmly print a giant base-unit integer and make it look authoritative.

The fix was to stop pretending. When decimals are missing, Auralis now uses an explicit policy: hide the amount and say why. The row and detail screen both surface that the balance is hidden until token decimals load, instead of guessing and risking a lie. Sometimes the senior-engineer move is not to be clever. It is to refuse to make up numbers.

### War Story: Two Alchemy token endpoints that look like twins but are not

This one is a classic integration banana peel. Alchemy has both `tokens/by-address` and `tokens/balances/by-address`. At a glance they look like the same endpoint wearing different hats. They are not.

`balances/by-address` is the ledger. It tells you the raw balances and gives you paging over address-network pairs. `tokens/by-address` is the annotated museum label. It can bring back names, symbols, decimals, and prices, but it is a richer payload with a slightly different job.

The trap would have been to keep using the richer endpoint everywhere and casually say the app “supports balances-by-address.” That is how roadmap docs drift away from reality.

The fix was to make the exact endpoint a first-class provider contract in the codebase, then let the ERC-20 holdings flow use it for what it is good at: authoritative raw balances. Metadata enrichment still comes from `tokens/by-address`, but now that is an explicit second step instead of an accidental substitution. The code now matches the sentence.

### War Story: Stale token metadata is a quiet liar

Token metadata bugs are sneaky because they rarely throw a dramatic exception. They just sit there and age. Yesterday's token identity can keep looking respectable long after the fetch that produced it has drifted into archaeology.

The fix here was not to build a giant token cache subsystem. That would have been premature theater. Instead, the app now has a simple freshness rule for ERC-20 enrichment: metadata gets a TTL, stale rows are marked honestly, and the token screen starts refreshing as soon as it appears. The stale badge is the important part. It tells the truth while the network catches up.

There was another cleanup tucked into the same pass: we stopped asking the enrichment endpoint for prices just to borrow a timestamp. That was the software equivalent of ordering a whole pizza because you wanted the cardboard box. `updatedAt` now means "when Auralis last enriched this token," which is a much saner thing to age out.

### Pitfall

Wallet switches are concurrency tests wearing a UX costume. If one wallet's slower token sync finishes after the user has already moved to another account, stale async work can start writing or messaging as if nothing changed.

The fix was to give ERC-20 sync a small coordinator that drops stale results when a newer scope takes over. This is not glamorous architecture. It is the kind of tiny guardrail that keeps a tab from becoming haunted when latency gets weird.

## Engineer's Wisdom

A good seam earns reuse. `ReadOnlyProviderFactory` already owned NFT, gas, and native balance creation, so token holdings belonged there too. This is the kind of decision that keeps a codebase boring in the good way.

Scoped persistence matters more than clever UI. For token holdings, the hard problem is not drawing a list row. It is making sure account A on chain X never bleeds into account B on chain Y, even after retries, stale cache, and tab switches.

Cached state is not a second-class fallback. In a provider-heavy app, cached rows are part of the product contract. If the network is shaky, the app still owes the user a truthful screen.

Exact endpoint support is a different thing from “close enough.” If a plan or ticket names a specific provider path, treat that as a contract and wire that path explicitly. Adjacency is not implementation.

Freshness beats false confidence. If data might be old, mark it old. A polished lie is still a lie.

## If I Were Starting Over...

I would probably carve out a dedicated token-holdings service a bit earlier, once it was obvious ERC-20 sync would need its own failure presentation and later pricing/history enrichment. The current store-plus-provider seam is clean enough for this phase, but the next layer of token features will want a more explicit coordinator.
