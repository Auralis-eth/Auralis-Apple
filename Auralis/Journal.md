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

### War Story: P0-401 stopped being a polite half-truth

`ContextSnapshot` had reached the awkward teenage phase. The shell was already using it, the chrome inspector was already showing it, and the strategy doc was already calling `P0-401` complete. But the ticket handoff still had the old scar tissue: “not a defensible 100% close.”

The reason was subtle. The schema had real scope, freshness, and library values, but Home launcher state was still half living off to the side like a neighbor borrowing your Wi-Fi. Pinned links and launcher routes were mounted product truth, yet the context contract did not model them explicitly.

The fix was not glamorous. We taught `ContextSnapshot` about module pointers, fed that from the real mounted Home launcher contract plus the pinned-links store, and pushed Home copy to read the shared snapshot instead of improvising its own version of the same story.

This is one of those senior-engineering moments that does not look dramatic in the diff. No new animation. No giant refactor. Just a contract that finally says what the product already knows.

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

### War Story: The tickets said "startable" long after the code had shipped

This audit turned up a very specific kind of failure: documentation drift with a straight face. The global Phase 0 reports were saying whole slices were complete, while several individual handoff docs were still written like someone had just sharpened a pencil and was about to begin.

That mismatch is not harmless paperwork. It changes planning decisions. A stale `Startable` at the top of a delivered ticket is the product-management version of a stale cache entry in code: somebody eventually believes it and makes the wrong move.

The cleanup was intentionally boring and therefore valuable. We normalized the explicit status in the ticket docs, wrote a hard closeout report for every P0 ticket except the still-blocked `P0-801` through `P0-803` set, and called out the exact places where the repo still lacks trustworthy closeout artifacts or validation signal.

The lesson is simple: architecture debt and documentation debt use the same disguise. Both pretend to be tomorrow's problem right up until they start steering today's roadmap.

### War Story: The ERC-20 tab looked like a CSV export wearing a tab icon

The provider-backed holdings work was real, but the screen still looked like the app had given up five minutes before the demo. A plain `List`, a few gray captions, and a token amount floating off to the right is not a product surface. It is a debug readout with better manners.

The fix was not to throw motion or gradients at the problem blindly. The right move was hierarchy. We turned the ERC-20 root into a scoped wallet surface with a summary card, explicit freshness, clear native-vs-ERC-20 distinction, and rows that actually scan: title, amount, metadata state, route affordance, and update time all have jobs now.

This is a useful reminder that data plumbing does not finish a feature. A backend-complete tab with weak hierarchy still feels unfinished because the human eye is the real integration point.

### Pitfall

The Xcode MCP test runner can fail in a particularly annoying way: not red, not green, just `No result` and a vague complaint that testing was cancelled because the build failed, while a standalone build reports success and no live compiler issues exist.

That is not validation. It is fog. The right engineering move is to document the exact limitation, keep the successful build signal, and defer the unit-test verdict instead of pretending the runner said something it did not.

## Engineer's Wisdom

A good seam earns reuse. `ReadOnlyProviderFactory` already owned NFT, gas, and native balance creation, so token holdings belonged there too. This is the kind of decision that keeps a codebase boring in the good way.

Scoped persistence matters more than clever UI. For token holdings, the hard problem is not drawing a list row. It is making sure account A on chain X never bleeds into account B on chain Y, even after retries, stale cache, and tab switches.

Cached state is not a second-class fallback. In a provider-heavy app, cached rows are part of the product contract. If the network is shaky, the app still owes the user a truthful screen.

Exact endpoint support is a different thing from “close enough.” If a plan or ticket names a specific provider path, treat that as a contract and wire that path explicitly. Adjacency is not implementation.

Freshness beats false confidence. If data might be old, mark it old. A polished lie is still a lie.

## If I Were Starting Over...

I would probably carve out a dedicated token-holdings service a bit earlier, once it was obvious ERC-20 sync would need its own failure presentation and later pricing/history enrichment. The current store-plus-provider seam is clean enough for this phase, but the next layer of token features will want a more explicit coordinator.
