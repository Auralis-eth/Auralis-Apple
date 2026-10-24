# Journal

## 2026-10-24 - The Artifacts Moved Into the Evidence Vault

Scheduling exposed an honest boundary: it does not merely name an output; it persists real artifact
drafts through an artifact store. Pulling that implementation into Runtime would create a circular
hallway and put evidence storage in the execution kernel. So the next move went the other direction:
`ArtifactCore` and `ArtifactStorage` joined `ReceiptsCore`, their final owner.

Both modules kept their names and independent tests. Consumers changed only the package address.
This is the evidence-vault model: Runtime may describe work, while receipts and artifacts own what
was actually produced and how it is durably stored. The combined owner passed 162 tests, five
consumers passed 627, and the graph guard plus Xcode build-for-testing remained green.

## 2026-10-24 - Eval Joined the Runtime Lab

`EvalCore` followed Performance into the RuntimeCore package without changing its module name,
public API, or 49-test suite. The move is conceptually tidy: evaluation consumes runtime traces and
performance records, so all of its inward dependencies now live under one package roof while the
target boundary still keeps its responsibilities visible.

This is another reminder that package topology and module topology are different maps. We removed a
shipping root, not the wall around evaluation. RuntimeCore and the three direct consumers passed 829
package tests, followed by the package-graph guard and Xcode build-for-testing.

## 2026-10-24 - Performance Packed Light

After the Playbook cycle untangling, `PerformanceCore` was refreshingly uneventful: one source file,
one test file, and no production dependencies. It moved under the RuntimeCore package while keeping
its module and test-target identity, and five consumers simply changed the product address in their
manifests. This is the ideal consolidation passenger—one suitcase, no prohibited imports, no
surprise pet in the carrier.

The lesson is that package-root removal should scale its ceremony to its dependency risk. We still
ran the full owner and direct-consumer proof—880 package tests, the focused graph guard, and Xcode
build-for-testing—but we did not invent a redesign where a relocation was sufficient.

## 2026-10-24 - The Playbook Stopped Borrowing the Receipt Warehouse's Clipboard

`PlaybookCore` looked ready to follow Planner into the RuntimeCore package until SwiftPM pointed at
a circular hallway: playbooks depended on `ArtifactCore` for a six-case output-kind enum, while
artifacts already depended inward on Runtime for actor attribution. Moving the whole artifact module
into Runtime would have made the package counter happy and the ownership model wrong. Artifacts and
their storage belong to receipts; they are evidence and outputs, not execution authority.

The fix was dependency inversion at the actual seam. Runtime now owns `ArtifactOutputType`, the
small vocabulary a playbook needs to say “this workflow may produce a brief or report.”
`ArtifactCore.ArtifactType` is a public typealias, so existing artifact callers keep their familiar
name and wire values. Then PlaybookCore moved intact beside Planner as another internal RuntimeCore
target. Think of it as returning the warehouse clipboard and keeping a copy of the six allowed
shipping-label names at the front desk.

The war story is useful: a package cycle is often a smoke alarm for one misplaced contract, not an
invitation to merge both buildings. The final graph passed 1,146 focused tests across the owner,
artifact, seven consumer packages, and the architecture guard, followed by Xcode build-for-testing.

## 2026-10-24 - The Planner Changed Apartments, Not Its Name

The first Runtime consolidation was intentionally boring in the best way. `PlannerCore` moved into
the RuntimeCore package, but it kept its module name, public API, source layout, and independent test
target. Consumers changed the address in their package manifests; their Swift imports did not change.
It is the architectural equivalent of moving an apartment building without renaming the tenants.

This is the safest pattern for turning dozens of package roots into a smaller set of owned packages:
first preserve module boundaries as internal targets, prove every direct consumer, and only then
consider source-level redesign. Package count is deployment topology; target boundaries still carry
the compile-time dependency rules. The new architecture guard makes that distinction executable by
requiring the Planner target inside RuntimeCore and refusing a resurrected standalone package root.

## 2026-10-24 - Search Took the Same Transaction Train

Once Music proved that a domain can own its luggage while AccountStorage owns the train timetable,
Search was the natural second passenger. `SearchHistoryRecord`, its complete snapshot, and its
capture/delete/restore participant now sit beside `SearchHistoryStore` instead of camping in the
mixed PrimaryModels warehouse and the account coordinator.

The important part is what did *not* change. Account removal, overwrite, undo, and rollback still use
one `ModelContext` and one save boundary. App composition hands AccountStorage a type-erased ticket;
the coordinator never learns a Search field, and Search never gets permission to commit independently.
Tests pin the old SwiftData entity name, every restored field, cross-account isolation, and a forced
late failure. In other words, moving the passenger did not split the train.

## 2026-10-24 - The Music Crate Moved Without Reversing the Conveyor Belt

The next mixed persistence model looked easy to relocate: pick up `MusicLibraryItem`, put it beside
the music indexer, and teach AccountStorage where it went. The compiler caught the architectural trap
immediately. MusicFeature requires the newest platform generation, and—more importantly—Operators is
supposed to depend on Crypto, not the other way around. Making AccountStorage import MusicFeature
would have been like moving a crate to the correct warehouse by reversing the whole conveyor belt.

The fix was dependency inversion at the transaction seam. MusicFeature now owns the model, its domain
values, its complete snapshot, and its account-scoped capture/delete/restore participant. AccountStorage
owns a small type-erased participant contract and still controls the only `ModelContext`, transaction,
save, rollback, and undo registration. App composition introduces the two. That preserves atomicity
without teaching the account package anything about music.

The first package compile exposed a second stowaway: `AuralisTestSupport` still carried a
music-specific SwiftData fixture. Pulling MusicFeature into shared test support would have rebuilt the
same reverse dependency in miniature, so the fixture moved beside its actual test consumers instead.

The useful lesson is that final ownership and transaction membership are separate questions. A model
can live with its domain while a lower coordinator operates on it through an injected participant. The
coordinator owns *when everything commits*; the domain owns *what its data means and how it is restored*.

## 2026-10-22 - The Finish Line Got One Name

The ownership architecture was complete, but its paperwork described that fact like several witnesses
who agreed on the event and disagreed on the headline. The canonical architecture, founder covenant,
authority audit, project memory, known limitations, ship-readiness list, and future-work backlog now use
one boundary: the **ownership and sovereignty restructuring is complete** for its Phase 1 scope.

The important distinction is between finishing the road and deciding where to drive next. The portable
ownership vocabulary, package boundaries, authority separation, receipt integrity support, and root-owner
audit are the finished road. Populating optional provenance on individual production receipts, defining an
identity bridge when a real consumer can specify it, or someday adding governance or economics are new
destinations. Their open checkboxes no longer make the completed construction project look unfinished.

## 2026-10-22 - One Dashboard, Not Three Archaeological Sites

AuraPlay's code had reached the finish line, but its documents were still arguing from different points on the journey. One file said provider discovery was authoritative while another promised a fallback to the old index. One said the schema was flat while another sent readers looking for a migration plan that had been deliberately deleted. The code was not confused; the map was.

The cleanup treats documentation like a cockpit: each instrument gets one job. `AuraPlay-Status.md` is the detailed as-built record, `AuraPlay-LLM-Context.md` is the compact mental model, the README is the ownership and navigation map, known limitations name accepted constraints, and the physical-device suite is the only manual hardware gate. Durable evidence and device cases moved into those homes; three overlapping requirements/audit/master-checklist files were retired to git history. Whole-app visual concerns stay in the P0 design checklist instead of sneaking back into a music-specific backlog.

The memorable rule is simple: completed plans are scaffolding, not architecture. Once the building stands, preserve the load-bearing facts and take the scaffolding down—or the next engineer will climb it and wonder why it leads through a wall.

## 2026-10-22 - Five Roles, Six Columns, and One Hash That Must Not Move

Phase 1 asked for ownership vocabulary. The interesting work turned out to be in the receipt ledger,
where adding four optional fields meant proving that the several hundred receipts an upgraded install
already holds would hash to exactly the same bytes afterwards.

The mechanism was already there — `ReceiptIntegrityEnvelopeVersion`, optional fields omitted when
`nil` — but the version gate had a trap in it. `receiptID` is gated behind `>= bindsReceiptID` because
it is non-optional and would otherwise change v0 bytes. Applying the same gate to the new provenance
columns looked symmetrical and was the wrong move: gating them means they are outside the hash on any
row whose *version column says v1*, so an attacker could write provenance onto an old row, or
downgrade a v2 row and then rewrite its provenance, with the chain hash still verifying. The columns
are optional, so they need no gate to preserve old bytes. They are hashed unconditionally and the
version bump is a *statement* rather than a switch — it is what lets a reader tell "this receipt says
no resource was affected" from "this receipt predates the question".

The proof that nothing was rehashed is now a byte, not a paragraph: the golden vector this file
published before Phase 1 is asserted against an explicit `envelopeVersion: bindsReceiptID` and must
never change again.

The parent-receipt contract produced the other lesson. Duplicates and self-reference are refused, and
beneficiaries on an `OwnershipDescriptor` are normalized, and the asymmetry is not inconsistency:
naming a beneficiary twice states one fact twice, while naming a parent twice states something untrue
about causality — and a receipt is immutable the moment it is signed, so there is nowhere to repair it
afterwards. The *third* rule, that parents must already exist, is enforced before the write and
reported as **unattested** at verify time, because a parent can stop existing without anyone touching
the row that names it. Writing the test for that was the useful part: a deleted parent is not
independently reachable. Remove a row from the middle of an account's chain and `accountSequenceID`
breaks; leave the anchor behind and "protected heads without persisted receipts" fires. The one shape
that leaves every survivor internally consistent is deleting a whole account *and* its anchor — which
is precisely the scenario this package already documents as the hard case for completeness. The branch
is reachable, but only there, and now the test says so instead of assuming it.

Last, the thing worth repeating from the identity half: `PrincipalID` refuses only the empty string. It
does not trim, because validating the trimmed form while storing the raw form would make the
initializer and `rawValue` disagree about what the value is. A label that helps the system track a bag
must not also claim to describe its owner.

## 2026-10-21 - The Mechanism Was Right and the Sentence Was a Lie

Two agents had left fixes in the working tree that nobody had read — about three hundred lines across
the policy gate and the receipt ledger, the two places this branch's worst bugs have historically
lived. Reading them was the whole job. The fixes themselves held: every claim their comments made
turned out to be true when checked at the call site, including the one that had kept a finding open
for two rounds on the premise that normalizing an address would change what receipts hash. It does
not, and the type that proves it is forty lines long.

The two defects were somewhere else entirely, in a fix that was itself correct. Clearing receipts had
been moved to run *after* the database transaction commits, which is the right order — the
transaction rolls back whole, so the irreversible step should go last. But both steps shared one
error handler, and that handler's message says "Changes in that phase were rolled back, so you can
retry the privacy reset safely." By the time the receipt step can fail, the transaction has committed:
the search history, the token holdings, the music library, the playlists are all already gone. Every
word of the mechanism was right. The sentence next to it told the person their data had survived.

That is a kind of bug worth naming, because it is invisible to the usual questions. Nothing was
unsafe, nothing was unordered, retrying really did work. What failed was the account the system gave
of itself — and in a privacy feature, the direction of that error matters more than its size. The
second defect was smaller and more embarrassing: a new test double had been inserted directly between
an `@MainActor` line and the class it annotated, quietly stealing the attribute from a neighbour
nobody had touched.

The reason the first one reached us is the same reason as the last three of its kind. The test double
for the failing step *had* a way to inject a failure. No test ever used it. Coverage that exists and
is never exercised reads, from the outside, exactly like coverage.

## 2026-10-21 - The Dashboard Was Showing Yesterday's Weather

The ship-readiness audit had a curious split personality: its newest round correctly described an
active, heavily audited branch, while its front-page summary still insisted nobody had read a file or
run a test. The repository had moved again too—twenty working-tree entries were present while the
metadata still called the tree clean. That is the documentation equivalent of a cockpit gauge stuck
on yesterday's reading: all the detailed machinery can be right and the first thing a pilot sees can
still send them the wrong way.

The fix was deliberately surgical. The audit now has a dated live-state override, a current summary,
fresh scope counts, and an explicit label on the original integration table as historical inventory.
The lesson is simple: long-running audit documents need a small authoritative “now” section, while
older measurements should be preserved as history rather than allowed to masquerade as current state.

## 2026-09-28 - Identity Became a Shipping Label, Not a Personality Test

Phase 1's identity boundary is deliberately boring: `PrincipalID` is a stable, non-empty, opaque
label. Auralis may compare it, store it, serialize it, and pass it between boundaries, but it may not
hold the label up to the light and guess whether it belongs to a person, agent, company, wallet,
blockchain address, DID, protocol, or network. Identity producers choose stable collision-resistant
values; consumers do not reverse-engineer meaning from their spelling.

That decision keeps the portable value in `AuralisPrimaryModels` without resurrecting
`AgentIdentityCore` or stretching `RuntimeCore.ActorRef` into a universal identity system. Runtime
attribution can remain rich and contextual while ownership relationships use the smallest shared
vocabulary. Beneficiaries are ordered and unique so equality and encoding stay deterministic, and
receipt causality starts with validated parent receipt IDs rather than an early taxonomy of causal
verbs.

The memorable rule is the luggage-tag rule: a tag helps the system keep track of the bag; it does not
authorize opening the bag, describe its owner, or reveal where they live. Authority, presentation,
and domain meaning must come from explicit surrounding context.

## 2026-09-12 - The Packages Got Shipping Crates, Not One Bigger Warehouse

The consolidation map had the right instinct—fewer manifests without flattening target boundaries—but
an open-source library needs a different kind of border from an app workspace. We recorded ARCH-004
to separate publication units from Auralis integration packages. The memorable analogy is a shipping
yard: Auralis can stack several crates onto one internal pallet for convenient handling, but the crates
still need their own labels, dependency lists, tests, and release schedules if another developer should
be able to order only one.

The goal hardened after review: every extracted core, adapter, storage implementation, engine, and
operator pack gets its own open-source shipping crate—not merely an internal target in a larger public
box. That reverses the temporary AuralisCrypto consolidation and extends the rule to provider adapters,
NFT layers, wallet-vendor adapters, and runtime companions such as planning, artifacts, scheduling,
performance, and evaluation. Private aggregates may still make the Auralis workspace pleasant, but
they are forklifts, not packaging: each component must resolve from its own tagged repository URL and
advance without publishing its neighbors.

Foundation stays narrow instead of becoming the drawer where every useful type disappears. Ethereum
chain aliases move out of the governed runtime. Receipt mechanics become a generic ledger with Auralis
schemas layered above it. Policy reports decisions through a recorder seam without owning receipt
storage. Operator packs remain separate from their registry, and the already-clean AuraPlay media,
audio, and video packages become separate first-class releases.

The larger lesson is that source ownership, workspace convenience, and public versioning are three
different maps. Forcing them to share every border makes the local graph look tidy while exporting the
entire app's baggage to small consumers.

## 2026-09-07 - Mission Control Learned to Refuse an Unreceipted Launch

The approval button used to behave like a rocket switch whose flight recorder was installed after
liftoff: execution resumed first, then Mission Control tried to save the human decision. A storage
failure in that narrow gap could produce a real effect without its promised audit evidence. Approval
now fails closed. The decision receipt must land durably before the governed proposal can resume; if
storage is unavailable, the request stays pending and the operator gets a clear retryable error.

Two quieter trust bugs went with it. Approval reconciliation now reads complete exported receipt
history instead of peeking through a 500-row keyhole, and receipt/artifact read failures show explicit
degraded-data banners while preserving the last known snapshot. Empty state and broken evidence are
not the same story, so the UI no longer tells them with the same blank page.

Artifact version history had one last trapdoor: its loader still translated a storage outage into an
empty list, erasing the last trustworthy versions from the detail screen. It now keeps those versions
on the shelf, raises the degraded-evidence warning, and clears only that warning after a successful
retry. Browser-history and version-history warnings are tracked separately, like two alarm circuits,
so repairing one cannot switch off the other by accident.

The test suite also turned out to be a fire alarm with its batteries beside it. The package tests were
present but the macOS lane could not compile an iOS-only text-input modifier, and the test target lacked
its direct OperatorsFeature dependency/import. The macOS guard and package wiring now let the full suite
execute, while CI invokes SwiftPM directly instead of relying on a package scheme that discovered zero
tests. The memorable rule: a test file is evidence only after the release lane actually runs it.

## 2026-09-06 - The Watchlist Got a Memory and the Report Kept Its Receipts

The first On-Chain Watch looked like a guard at a desk with a sticky note: it could inspect one address,
but the note disappeared when Mission Control was rebuilt. Watch targets now persist per active identity,
support multiple accounts or contracts, and stay isolated when the user switches identities. The operator
still enters through the same governed, read-only pipeline; persistence changes what it remembers, not what
it is allowed to do.

The second gap was provenance. Reports summarized receipt-backed observations but did not keep the IDs of
the receipts they summarized, like a research paper whose bibliography said only “trust me.” Observed
activity now carries its source receipt ID into `Artifact.relatedReceiptIDs`, and operator requests carry
their originating playbook ID into `Artifact.creatorPlaybookID`. That makes the artifact browser's existing
receipt and playbook links factual rather than inferred. The lesson: a safe operator needs both a fence
around its authority and breadcrumbs back to every fact it used.

## 2026-09-06 - The Treatment Plan Joined the Receipt

Routine evaluation already chose a deterministic next action, but that decision lived only in the detailed evaluation store. The routine receipt now carries the same decision—complete, request human review, or repair evidence and retry—so an auditor does not have to reconstruct the scheduler’s final choice by joining private implementation details. An end-to-end runtime test follows a real routine through execution, evaluation, persistence, and receipt creation. The lesson is simple: if the pipeline claims it decided what happens next, that decision belongs on the paper trail.

## 2026-09-06 - The Oldest Approval Stopped Hiding the New Ones

The approval-age trigger had a queueing bug disguised as sensible bookkeeping. It always watched the
oldest pending approval. Once a routine handled that timestamp, any newer approval could grow old behind
it without producing a newer signal—as if a receptionist kept announcing the first person in line and
never noticed everyone waiting behind them.

The approval registry can now return the newest request that has actually crossed a supplied cutoff. The
runtime asks for that monotonic timestamp at the thirty-minute boundary, so a fresh request is ignored,
an overdue request is visible, and each later request can advance the event signal even while older
requests remain unresolved. A regression test keeps the cutoff and multi-request behavior honest. The
broader lesson is that event triggers need progress markers, not merely true/false conditions: “something
is pending” cannot tell a scheduler whether it is seeing yesterday's event or a new one.

## 2026-09-06 - A Green Run Cannot Lose Its Package or Paper Trail

The scheduler had two trapdoors hidden under its happy path. If artifact storage threw, `try?` quietly
discarded the error and the run could still wear a green “success” badge with no artifact to show for it.
Artifact creation now behaves like handing a parcel to a courier: until the handoff succeeds, delivery
has not happened. A failed save becomes an infrastructure failure in both execution history and the
performance stream, with a stable reason that can join the failure-pattern dashboard.

Receipt storage had a similar vanishing act. Runtime-owned receipt failures now illuminate an observable
warning light and emit a correlated activity update saying the audit evidence is incomplete. That event
cannot replace the missing durable receipt—the whole point is to avoid pretending it can—but it keeps
the live console and session honest about the degraded trail. The lesson: success is an end-to-end
contract. Producing useful work and proving what happened are separate handoffs, and neither deserves a
silent question mark.

## 2026-09-05 - Trust Metrics Learned to Tell the Whole Story

The scheduling pipeline used to stop its paper trail at evaluation, like a doctor writing down a
diagnosis but forgetting the treatment plan. Evaluation results now carry a persisted next action:
complete successful work, request human review for failures, or repair missing evidence before retrying.
That makes the scheduler's final decision inspectable instead of something callers must reconstruct.

The performance scorecard also stopped treating every locked door as a policy veto. Blocks now retain
their source—policy, authority, context, unsupported capability, infrastructure, or other—so the
dashboard can show a real policy-block rate alongside the broader blocked rate. Approval rate now has a
similarly precise contract: approved decisions divided by resolved human decisions; pending requests and
deferred choices do not quietly distort the denominator.

One final trap was the database equivalent of sweeping broken glass under a rug: execution and
performance stores used `try?`, turning failed writes into apparent success. Those paths now catch and
log fetch, encoding, and save failures with enough context to diagnose the affected record. The lesson:
trust telemetry is only trustworthy when categories, denominators, decisions, and storage failures are
all explicit.

## 2026-09-05 - The Playbook Vault Stopped Eating Error Notes

The playbook store used to answer a failed fetch with an empty shelf and a failed save with a polite
nod. A handful of `try?` expressions had turned database trouble into plausible-looking success—the
persistence equivalent of a librarian losing a book and quietly telling you the catalog was always
empty.

Playbook storage now throws fetch, decoding, encoding, and save failures across its protocol boundary.
Mission Control keeps the last trustworthy snapshot and presents an accessible error instead of
claiming the change worked. Background routines fail closed with a recorded reason, while startup
seeding emits an explicit system log. The lesson is simple: persistence is part of the product
contract, so failure must travel far enough for both the user and the audit trail to see it.

## 2026-09-05 - Two Scorecards, Two Jobs

The early evaluation types had acquired an identity crisis. `PerformanceRecord` was introduced as a
small runtime-boundary scorecard, then richer evaluation and operational-history types arrived and its
comment effectively called it obsolete. That made the architecture read like a kitchen with two order
tickets where one claimed nobody should use it.

The boundary is explicit now: `PerformanceRecord` is the portable P0.5 summary, `EvalResult` is the
detailed criterion verdict, and `PerformanceEvent` feeds operational history and aggregates. Direct
round-trip tests pin both the outcome specification's legacy migration behavior and every field of the
performance summary. The lesson is that a stub can be deliberately small, but it cannot be vague about
its job—or untested simply because it fits on half a screen.

## 2026-09-05 - Every Passenger Gets Their Passport Checked

The deterministic-check registry had a classic velvet-rope bug: a watchlist could bring several
targets to the door, but only the first target showed identification. The whole list is now decoded at
the governance boundary, and every address, chain, and ENS name must pass before the run proceeds.
Malformed serialized lists fail closed instead of falling back to the convenient scalar fields.

Freshness also stopped consulting the wall clock behind the auditor's back. Runtime proposals now
record both when their context was refreshed and the instant at which freshness was evaluated; the
check uses only those two recorded values. Replaying the same proposal therefore produces the same
verdict, while missing timestamps fail closed. Every production policy tool and operator requires the
freshness check. Finally, the registry verifies that a check returns the same ID under which it was
requested—because a boarding pass that says a different passenger's name is not evidence, even when
it has a cheerful green checkmark.

## 2026-09-04 - The Flight Recorder Stops Accepting “Somebody, Somewhere”

Actor attribution used to resemble a security-camera clip labelled “a person did a thing.” The
important nouns existed, but several constructors still allowed a nameless workflow, a model with no
inference provenance, or a receipt with no workflow filing key. Those are tolerable migration facts;
they are terrible defaults for new evidence.

The kernel now rejects unnamed non-human actors and models without provenance. Proposals, worklog
steps, and scheduled execution records carry an explicit workflow-run reference plus an authority
lifecycle (`pending`, `resolved`, `denied`, `notApplicable`, or `legacyUnknown`). Standalone actions
receive their own stable run identity, and new receipt drafts similarly receive a correlation identity
instead of disappearing into the `nil` drawer. Old JSON still decodes into visibly legacy states, so
hardening the front door does not burn the archives. The lesson: “unknown because this happened before
the schema existed” and “unknown because today's caller forgot” must never share the same code path.

## 2026-09-04 - The Context Suitcase Gets A Weight Limit

The customs desk was checking passports, but it would still accept a suitcase the size of a studio
apartment. Context contracts could also shrug about where a field came from or how old it was, and an
operator could immediately pour every approved field back into an ordinary dictionary—like removing
the evidence tags the moment a bag cleared inspection.

The contract is strict now: every field requirement must name its authoritative source and a concrete
maximum age. Legacy declarations missing either fact fail decoding instead of quietly inheriting a
weak default. Bundles are capped at 64 fields, 128 bytes per key, 16 KiB per value, and 64 KiB in total;
the shared governance boundary rejects excess before an operator or model sees it. Finally,
`GovernedContext` only supports field-by-field typed lookup, so provenance, classification, and
freshness stay attached all the way to the consumer. The lesson is wonderfully mundane: governance
is not merely deciding who enters—it is controlling what they carry and keeping the luggage tags on.

## 2026-09-04 - Context Got A Customs Desk And A Tamper-Evident Passport

The first context contracts checked the guest list, but every guest arrived carrying an ordinary
string. A field marked `sensitive` could therefore smuggle the actual secret in its suitcase, and an
operator received a plain dictionary that threw away every provenance stamp immediately after the
inspection. The guard worked; the chain of custody did not.

Context values now make raw sensitive bytes unrepresentable. Sensitive fields carry either an opaque
vault reference or a redaction marker, while old raw strings are quarantined as redacted during
construction and decoding. Sources use a closed kernel vocabulary instead of costumes made from
arbitrary strings. Successful validation produces a `GovernedContext`—a passport retaining the
approved bundle, contract identity and version, validation time, provenance, and a value-free SHA-256
evidence digest. Operators accept that passport directly, and the routine worklog records its safe
manifest rather than merely saying “five fields.”

The reusable `ContextGovernanceBoundary` is the customs desk: schedulers use it today, and future
agent or plugin execution paths have one canonical gate instead of copying validation logic. Built-in
context also grew beyond name tags to include the playbook's source, trigger class, and permitted
flows—all facts the definition can honestly attest without pretending wallet or holdings data was
loaded. The lesson: privacy labels are not seatbelts unless the type system makes the unsafe state
hard to construct, and audit metadata is useful only if it survives past the checkpoint.

## 2026-09-03 - The Flight Recorder Learned To Use A Fuse And A Warning Light

The critical event streams were called lossless, but their live queues were unbounded. That is like
protecting every page of a flight log by piling paper into the cockpit until nobody can reach the
controls. They also treated an expired checkpoint as an ordinary first launch, silently replaying
whatever pages happened to remain after retention pruning.

Reliable subscriptions now use bounded buffers. If a receipt or performance observer falls behind,
the bus closes that stream and the observer reconnects from its last successfully processed durable
checkpoint. A checkpoint that has fallen outside retained history increments an explicit replay-gap
health counter, so Mission Control shows degraded audit continuity instead of a reassuring fiction.
That unhealthy state survives reconnects. Persistent history also assigns a monotonic append sequence,
so equal timestamps cannot scramble reads, pruning, or checkpoint replay.

The memorable rule: reliability does not mean “infinite RAM.” It means bounded failure, durable
recovery, and a warning light whenever recovery can no longer reconstruct the whole story.

## 2026-09-03 - The Event Bus Put Names On The Reserved Seats

Reliable subscribers already had names, but the bus treated those names more like sticky notes than
seat assignments. Mission Control only reported names beginning with `runtime.`, even though the API
promised health for any named critical consumer. Worse, two consumers could claim the same name and
race to advance one durable checkpoint—the event-processing equivalent of two people sharing one
bookmark and insisting neither skipped a chapter.

Named reliable subscriptions now have an explicit health-reporting flag, independent of spelling,
and a second subscription with the same identity deterministically replaces and finishes the first.
Regression tests cover arbitrary subscriber names, duplicate claims, and a checkpoint whose event has
already aged out of retained history. The lesson is small but sticky: an identifier becomes a contract
the moment correctness depends on it.

## 2026-09-03 - The Event Bus Stopped Swallowing A Broken Pencil

The runtime could previously announce an event live even when its SwiftData flight recorder failed
to write it, because storage errors disappeared behind `try?`. That made the control room look calm
while the durable log quietly developed a hole. The history store now throws write failures back to
the bus. Live delivery deliberately continues, but Mission Control sees `runtime.history` as unhealthy
with an explicit failure count, so degraded durability is visible instead of fictional.

The design lesson is that availability and durability are different promises. A station loudspeaker
should keep working when the archive cabinet jams, but the warning light must come on immediately.

## 2026-09-03 - The Event Bus Gave Its Flight Recorders Reserved Seats

The runtime event bus already behaved like a busy station loudspeaker: every listener heard the same announcement, but a slow listener could fill its small buffer and miss an older message. That is fine for an activity feed; it is not fine when the listener writes audit receipts or performance evidence. A dropped capability revocation is not “eventual consistency”—it is a hole in the story.

Critical observers now board through named, lossless subscriptions. Each keeps a durable checkpoint, replays retained history oldest-first after a restart, and buffers live arrivals while replay is being assembled so the history-to-live seam has no crack. Receipt replay is idempotent by runtime event ID, which also closes the awkward crash window between saving a receipt and advancing its checkpoint. Ordinary UI feeds keep their bounded buffers so an abandoned screen cannot grow memory forever.

Mission Control can now see the health of each critical subscriber, including connection state, delivered count, and drops, instead of relying on one anonymous global counter. Privacy reset clears checkpoints alongside event history. The engineering lesson is that “publish/subscribe” describes plumbing, not reliability: consumers with different consequences need different delivery contracts.

## 2026-09-03 - The Tool Labels Finally Became Contracts

The governed runtime already had a locked tool room, but several of the most dangerous tools were still stored in boxes labeled merely “wallet stuff.” Their `ToolDefinition`s technically had schema slots, yet signing, transaction, approval, and plugin actions left those slots blank. That meant the executor was the first component to fully understand malformed cargo—far too late in the checkpoint line.

The shipping catalog now gives every policy tool an explicit input and output contract, including Ethereum-aware quantities, calldata, chain IDs, signatures, transaction hashes, and dynamic plugin parameters confined to their own namespace. Deterministic checks independently verify payload identity, supported EVM chains, and bounded token approvals before policy or judgment can clear execution. Tool registration also refuses malformed definitions, missing check bindings are caught during runtime bootstrap, and every state-changing registration must promise a receipt.

One tiny bug carried an outsized lesson: the address validator's message demanded a `0x` prefix while its implementation quietly accepted addresses without one. Security validation is a bouncer, not a motivational poster—the behavior matters more than the sign. The implementation and its package regression tests now agree, and the catalog suite prevents high-impact tools from drifting back to empty contracts.

## 2026-09-02 - The Flight Recorder Stopped Giving Up After One Broken Gauge

The after-tool hook had a subtle resilience bug: when receipt persistence failed, it immediately returned its report. That honestly surfaced the missing receipt, but it also skipped the performance signal and every additive observer—the audit equivalent of one broken gauge switching off the rest of the cockpit. Evidence sinks should not share a single fuse.

The hook now attempts every remaining emission and accumulates every failure into one report. A failed receipt still makes the governed run report incomplete evidence, while performance telemetry and all observers get their chance to record what happened. Regression coverage deliberately breaks the receipt sink and multiple observers at once, proving both continued delivery and complete failure reporting.

## 2026-09-02 - Policy Got Its Own Checkpoint, And The Flight Recorder Learned To Scream

The tool pipeline used to ask one guard to wear two hats: DomainJudge carried policy-flavored rules while the before hook described that as both judgment and policy. The distinction matters. Standing organizational policy and contextual judgment can change for different reasons, and an approval should not turn either one into a fossil. The pipeline now runs deterministic checks, a dedicated PolicyCore adapter, and the judge as explicit stages. Approved resumes repeat all three; only the exact escalation already approved is treated as satisfied. A newly blocking policy or judge still stops execution.

The audit trail also stopped practicing silent optimism. Durable receipt append failures and artifact-to-receipt linking failures now propagate through a throwing receipt boundary. If the external tool already ran, the caller receives an explicit “executed, evidence incomplete” failure and the session is marked accordingly. That wording is deliberately awkward because the truth is awkward: execution cannot be magically rolled back just because the flight recorder failed, and reporting an ordinary success would be worse.

Tests now exercise policy refusal before execution, policy changes between approval and resume, post-execution receipt failure, and direct storage failure propagation. Test-only pipeline conveniences live behind DEBUG; production composition still has to name every evidence sink.

## 2026-09-02 - The Tool Room Split Its Keys

The governed runtime previously handed one backstage key to both the runtime host and the operator package. It worked, but that key opened two different doors: registering a tool and assembling the entire execution pipeline. Those privileges are now separate. Operators receive only the registration key, while `RuntimeKit` alone can assemble the judge, executor, hooks, and production evidence sinks.

The pipeline constructor also stopped providing convenient in-memory defaults for receipts, worklogs, events, and performance. Production composition must now name every evidence destination explicitly—the architectural equivalent of requiring the flight recorder to be installed before the aircraft can leave the hangar. A repository-wide architecture test patrols every first-party package source tree so a future module cannot quietly import the composition SPI or construct execution authority outside `RuntimeKit`.

## 2026-09-02 - Approval Slips Became One-Time Boarding Passes

The action boundary already knew how to ask for approval, but two loopholes remained. A proposal could write “owner approval required” on its paperwork and still walk through if the judge otherwise said yes, and any caller holding an `ApprovalRequest`-shaped value could try to present it as authority. That is like a security desk reading the note on a parcel but never checking the signature—or accepting a photocopied boarding pass forever.

The runtime now keeps process-local custody of every approval it actually emits. Named approval requirements force an escalation, the exact request is bound to the exact registered tool, and approval is atomically consumed on first use. Altered, fabricated, stale, and replayed requests fail closed. A successful approval still returns through the whole checkpoint line: tool identity and impact matching, input validation, fresh deterministic checks, capability authority, execution, worklog, events, and receipts. Approval skips only the question that was already answered.

The intentionally conservative wrinkle is that execution authority does not resurrect after process death. Mission Control may reconstruct history from durable receipts, but a stale UI row cannot silently become a live execution token after relaunch; the action must be judged again. Security-sensitive continuations should prefer a fresh inconvenience over undead permission.

## 2026-08-28 - The Social Ledger Learned To Clean Up Without Forgetting The Plot

Social joins used to leave their coat on the chair when the relay vanished: the invite was already persisted before subscription, so an offline failure could look half-joined after relaunch. The join transaction now behaves like a careful hotel check-in. If the relay cannot start, it tears down the inbound pump, releases runtime ownership, removes the saved invite, and never reaches wallet verification. Retrying begins from a clean lobby instead of a haunted room.

The event projection also learned to explain a firm “no.” Mutations after session end, unverified authors, owner-only violations, removed participants, and mismatched vote authors now produce stable rejection classifications before persistence. The live adapter turns those classifications into privacy-safe receipts and operational logs containing public IDs and categories—not relay topics, ciphertext, signatures, or shared content. That makes incidents observable without turning observability into a second data leak.

Retention required the most important negative design decision: never chop the front off an active append-only story. Pruning removes entire old terminal session graphs only when no outbound event is pending, while stale invites and cursors leave with them. Ritual occurrence history keeps only its newest bounded claims. Mission Control now preflights every ritual recipe too, showing missing playbooks and disabling Run when no executable step exists. The stage manager can still run a partial rehearsal, but can no longer pretend an empty orchestra is ready.

## 2026-08-28 - The Notification Center Got A Concurrency Chaperone

Ritual notification settings met Swift 6's strict concurrency checker at the door. The adapter claimed to be `Sendable` while carrying `UNUserNotificationCenter`, a framework reference that does not make that promise. In other words, it wore a safety badge while escorting an unchecked guest between concurrency domains. Making the adapter an actor gives the notification center one guarded home and preserves the small async protocol seam used by the settings model.

The status mapping had a second, quieter trap: a multi-statement function needs an explicit `return` before its switch expression so the compiler can infer the result cases. With both boundaries stated plainly, live diagnostics are clean and the full Auralis scheme builds successfully.

The final package run caught a related migration pothole that the app's fast plan could not see: Mission Control's standalone fixtures still used pre-attribution initializers. Giving scheduled/manual executions an explicit actor, and receipt fixtures an explicit authority value (including honest `nil` when none exists), restored the package as an independently buildable boundary instead of letting the app target lend it a false sense of safety.

## 2026-08-27 - The Ritual Finally Filed Its Group Paperwork

Collaborative rituals used to create a shared session and toss artifacts into it, but the social ledger never heard the beginning or end of the story. Mission Control was waiting for `ritualRunChanged` events like a departures board waiting for trains that never radioed the station. The runtime now records the session and participant, emits started and terminal ritual states, runs every playbook under the shared correlation ID, and files both artifacts and receipts into the local session and deterministic social projection. The regression test starts at the real ritual executor and finishes at the replayed projection; it no longer hires a synthetic event to play the hero.

Scheduling also gained a longer memory. An in-process actor claim still stops a foreground tap and background refresh from colliding, while completed calendar occurrences now survive store recreation. This is deliberately “don’t repeat completed work,” not magical exactly-once execution after a crash halfway through an external side effect—that stronger guarantee still belongs at each governed tool’s idempotency boundary.

The trust boundary got a name too. Installation-local participants are explicitly `local` and their coordination events never enter the relay outbox. Wallet-verified identities remain the only authors whose events are eligible for relay delivery. It is the difference between a handwritten note on the rehearsal-room whiteboard and a signed message mailed to the whole group: both are useful, but pretending they carry the same proof would be how a friendly feature becomes a security bug.

One nearby migration taught the compiler a useful lesson about receipts. Every writer now states what authorized the action—direct human approval or standing policy—instead of leaning on optional shorthand or silently omitting the answer. The build is green again, and privacy-reset tests now recognize social coordination as a first-class cleanup phase rather than an unexpected guest in the completion list.

## 2026-08-27 - Rituals Stopped Calling An Empty Stage A Show

The ritual engine had a wonderfully dangerous piece of optimism: if it found zero installed playbooks, it still stamped the ritual as “run” and moved the next scheduled attempt a day or a week into the future. The orchestra never arrived, but the stage manager filed a glowing performance report. Ritual runs now return an explicit aggregate result—completed, partial, failed, skipped, or already running—and a skipped empty run does not advance the calendar. An actor-isolated claim also prevents a background refresh and a “Run now” tap from playing the same occurrence twice.

Human routines also learned the difference between “24 hours later” and “tomorrow morning.” Morning Review and Weekly Reflection now carry wall-clock schedules with a persisted time zone and weekday, letting Foundation handle DST rather than asking a stopwatch to impersonate a calendar. Mission Control exposes those schedules, expected steps, missing steps, and the last attempt’s result, while notifications report outcomes only when permission already exists. No surprise permission ambushes from a background task.

Shared agent context finally became a real contract instead of a poetic synonym for “some artifacts.” The social event log now carries a bounded, provenance-labeled summary with artifact references and expiration, rejects unverified authors during deterministic projection, persists it through the encrypted outbox, and presents it in the session UI. Raw prompts, credentials, provider internals, and arbitrary memory have no doorway into that payload. Think of it as sharing the meeting brief and its filing-cabinet references—not photocopying the team’s entire desk.

## 2026-08-27 - The Social Relay Stayed Behind The Gate

Social v1 grew real machinery: encrypted per-session relay envelopes, a durable event/outbox log, wallet-signed join verification, Mission Control sync summaries, and a bridge from accepted queue decisions into AuraPlay playlists. That is enough to call the code foundation complete for the non-device scope, but it is not enough to call the public product proven.

This pass corrected the release paperwork and build settings back to that reality. `AURALIS_SOCIAL_RELAY_ENABLED` is `NO` in Debug and Release, and the docs no longer claim the physical QA suite was waived for public shipping. The bridge is built, but the inspection stickers are still missing: WalletConnect/IRN terms, quota, retention, reliability evidence, and two-device wallet QA remain the line between "implemented" and "ready to expose."

The lesson is old but useful: a feature flag is not just a switch, it is a promise about what proof exists. When the proof is skipped by request, the honest thing is to leave the production door closed and make the code easy to validate next.

## 2026-08-21 - The Invite Learned To Ask For ID

Phase 3 gave Social v1 a real door check. The core challenge was already written down, but now the app has `SocialWalletJoinVerifier`, which parses the CAIP-10 account, asks a wallet connector to verify ownership with the exact session-scoped challenge text, and only then lets `SocialJoinChallengeValidator` mint a participant proof. The wallet layer still owns real cryptographic verification; the social layer owns the rules around expiry, nonce replay, and session/topic matching. That split keeps the handshake honest instead of letting a pretty invite become a fake passport.

Phase 4 moved the collaborative product layer out of the imagination and into Mission Control. The runtime host now carries the durable social event log, and Mission Control derives per-session sync summaries from replayed events: pending outbound work, queue proposals, accepted queue items, and ritual run outputs. The shared-session detail now shows those signals directly, with the important caveat in plain sight: queue sync is decision sync, not synchronized playback clocks.

The bridge inspection is still not done. We did not run real wallet apps, real relay traffic, or two-device physical QA. So the engineering state is better but the shipping state is unchanged: the bouncer knows what ID to ask for, the kitchen can see the group order, and the front door stays locked until live-device proof catches up.

## 2026-08-21 - Phase 2 Built The Outbox Before Opening The Door

Social v1 moved from "we know what the room should look like" to "the room has a ledger, a lock, and an outbox." The important new piece is `SocialEventLogStore`: it keeps the append-only event history, pending outbound event IDs, saved invites, relay replay cursors, and sync state together. That means a local edit can survive relaunch, wait for relay recovery, and replay without the UI pretending it already reached another device.

The join flow also got its canonical handshake. `SocialJoinChallenge` writes the exact message a wallet must sign: session, topic, account, nonce, and expiry. `SocialJoinChallengeValidator` does not pretend to verify cryptography itself; that belongs to the wallet layer. It does enforce the domain rules after the app says the signature is real: expiry, session/topic match, non-empty account, and nonce replay prevention. Think of it like a bouncer checking the stamped wristband after the cashier verifies the payment.

The app-side relay work is still behind the locked door. `SocialRelayCoordinator` can subscribe saved invite topics, seal outbound envelopes through an injected cipher, enforce payload size limits, publish through the WalletConnect/IRN relay adapter, clear the outbox after publish, and reject malformed inbound payloads without mutating state. But `AURALIS_SOCIAL_RELAY_ENABLED` stays `NO`. We deliberately skipped physical-device validation, so the honest ship label is: non-device foundation implemented, production-public collaboration still blocked. Good engineering sometimes means building the road and leaving the gate closed until the bridge inspection is real.

## 2026-08-21 - Social Sync Got A Ledger Before It Got A Party

The Social v1 plan needed code that behaved like infrastructure, not like a group-chat demo in a lab coat. This pass added the first relay-ready spine in `SocialCore`: versioned social event envelopes, portable invite payloads, wallet-proven participant identities, shared approval state, collaborative queue proposals, and a deterministic `SocialSessionProjection` reducer.

The important shape is append-only. Devices can receive events in different orders, drop duplicate relay deliveries, replay after relaunch, and still land on the same room state. The reducer treats relay payloads as untrusted: participants must be verified before they can author binding shared-state events, and vote/proposal payloads must match the envelope author instead of letting Alice cast Bob's vote by stuffing Bob into the JSON. That is the difference between "we synced some structs" and "we started building a coordination primitive people could eventually trust."

The app also gained a default-off `AURALIS_SOCIAL_RELAY_ENABLED` gate in Debug and Release configuration. That lock matters. The pure domain ledger can ship in the codebase, but the public relay-backed experience stays closed until WalletConnect/IRN terms, quotas, reliability, abuse handling, and two-device physical QA are proven. A good shared session is a kitchen ticket system: everyone sees the order, every change has an author, and nobody gets to yell "ship it" from outside the building.

## 2026-08-21 - The Social Door Got A Release Lock

The Human Coordination work reached the moment where a product idea can accidentally outrun its proof. Local shared sessions were real, but production-public social is a different animal: relays, invite keys, wallet proof, abuse handling, quotas, privacy, and two-device reality all have to stand up before the app can honestly say "collaborative" in public.

So this pass turned the fuzzy warning label into a release gate. Social v1 now has its own completion plan, relay readiness checklist, abuse and reliability contract, and two-device physical QA suite. The most important decision is written in big letters between the lines: app-only relay social is possible, but it is not magic infrastructure. If Auralis uses WalletConnect/IRN as an encrypted transport, we need terms, quotas, retention behavior, reliability assumptions, and acceptable-use evidence before shipping. The relay is a road, not a city hall.

The engineering lesson is simple: ambitious social features need paperwork before polish. A shared room without identity proof becomes theater. A relay without quota evidence becomes a pager at 2 AM. A collaborative approval without two real devices is still just a demo wearing shoes. The docs now make those gates explicit so implementation has something solid to aim at.

## 2026-08-21 - Shared Sessions Became A Room, Not A Sticky Note

The Human Coordination work had a classic almost-there problem: it had nouns with good names, but the verbs still needed to prove they could carry weight. A shared session could exist, a ritual could be listed, and a collaborative approval could count votes, but a real group workflow needs more than a clipboard. It needs the room, the people in it, the work they touched, and the receipts that prove what happened.

This pass tightened that loop. Social coordination state now has local persistence keys that privacy reset clears, so shared sessions do not become forgotten crumbs after a user asks the app to wipe local support data. Collaborative approvals now store the full `ApprovalRequest`, which means a vote can resolve the actual governed approval even if Mission Control's pending list has refreshed. Shared workflows run through the existing routine pipeline, then file their playbook, produced artifact, and routine receipt back into the shared session. Collaborative rituals also use the real runtime playbook IDs, so they create a session and produce visible work instead of politely running an empty recipe.

The product boundary is still deliberately modest. This is not a social network and not real-time multi-device collaboration. Think of it as a local coordination table: people, context, receipts, approvals, and rituals can sit together under one session. Phase 2 can build a larger town square later; Phase 1 needed the table to stop being imaginary.

## 2026-08-20 - Routes Became Doors, Not Name Tags

The local-first AI work had a trust problem hiding in the plumbing. The app could describe a remote-capable route, but some callers still treated that route like a decorative label: search only wanted Apple Foundation Models, autopilot fell back without actually asking a remote provider, and operators could stamp remote-ish telemetry from local string composition. That is like putting "cloud kitchen" on the receipt while the sandwich was still made in the break room.

This pass split the contract cleanly. `ModelRouting` decides where an inference should go; `ModelInferring` is the door that must actually open for routed provider inference. Search, autopilot execution, operator artifacts, and model-backed goal planning now flow through that split. Local Apple Foundation Models calls still work as local inference, but remote routes must run through the provider seam or fail instead of quietly producing local output with remote-looking paperwork.

Receipts learned the same lesson. Search assistant calls now emit inference receipts, governed tool artifacts persist their telemetry fields into receipt payloads, and autopilot planning records its model route, locality, privacy impact, timing, token estimates, and cost when planning used a model. Mission Control already had the shelf space for this evidence; the backend now brings the boxes.

The practical rule for future engineers is simple: never invent provenance after the fact. If a model route says remote, a provider client has to run. If a receipt says local, it should be because the on-device path really produced the answer. Trust UX is accounting with a user interface.

## 2026-08-20 - The AI Receipt Stopped Speaking In Hints

Local-first AI visibility had the right bones, but a few pieces were still more like labels taped to drawers than a real inventory system. Operators knew their routes because the catalog had route literals. Autopilot knew Apple Foundation Models because its performer carried its own static route. Search could call Foundation Models directly without asking the routing layer at all. And privacy impact was something a careful reader could infer from locality, which is not the same thing as a receipt saying it plainly.

This pass moved provider choice into `RuntimeCore.TaskKindModelRouter`, with stable `ModelTaskKind` keys and default local-first routes. Operators now name task kinds and resolve routes at execution time; autopilot resolves its route before running and fails closed if the Foundation Models performer is pointed at a non-local route; search resolves `ModelTaskKind.searchAssistant` before opening its Spotlight-backed model session. The trust fields got less coy too: operator and autopilot receipts now stamp `privacyImpact` and `durationSeconds`, Mission Control shows privacy impact and execution time in the session inspector, and the Context Bundle contract requires both fields from `OperatorExecutor`.

The useful lesson is that trust metadata should not be a crossword puzzle. Local vs remote, provider, model class, tokens, cost, time, and privacy impact belong in the same obvious drawer. If a future remote provider or DViances agent joins the system, it gets a route entry or router layer; the product surfaces should not need a new set of secret handshakes.

## 2026-08-20 - The Runtime Logbook Got A Bigger Shelf

The suspicious 500-event cap got a proper follow-up. Removing the cap proved the important distinction: a screen asking for the newest 500 events is a display choice, not a deletion policy. But an endlessly growing local event archive is not a shipping policy either; it is just a storage problem wearing a trench coat.

This pass made the retention guard explicit and much larger: `SwiftDataRuntimeEventHistoryStore.maximumStoredEvents` now keeps the newest 10,000 runtime events before pruning. That number is intentionally named, tested, and documented so future reviewers can argue with it in one place instead of discovering another mystery constant under the floorboards. Mission Control screens can still request small read windows, but storage keeps enough runway for long operator sessions, approval chains, context refreshes, and receipt-linked event trails.

The lesson: small magic numbers make terrible audit policy. If local storage needs a guardrail, name it, test it past the boundary, and say plainly what it is not. This is not an export-grade compliance archive. It is a pragmatic on-device retention guard for the runtime event history.

## 2026-08-20 - Mission Control Stopped Guessing How Big The Logbook Should Be (Superseded)

The runtime event store had a suspicious little number hiding in plain sight: 500. It sounded tidy, but nobody could point to a product requirement, retention policy, privacy decision, or ADR that made 500 the right answer. It was a filing-cabinet guess wearing a hard hat.

This pass removed the write-side pruning from `SwiftDataRuntimeEventHistoryStore`. Mission Control can still ask for the newest 100 or 500 events when rendering a screen, but storage no longer deletes older runtime events just because the display does not need them right now. That keeps the event bus honest: read limits are presentation choices; deletion is retention policy, and retention policy needs an actual decision. This was later superseded by a named 10,000-event local retention guard.

The same pass tightened the runtime control room. Approval decisions now append their receipts through `RuntimeHost`, so the receipt, `receiptCreated` event, session `receiptIDs`, approval ID, and execution update all land together. The Powers tab also grew real authoring controls: grant a capability to an actor for a chosen duration, or create an explicit denial like "No wallet access" / "No external network" without pretending inspect-and-revoke was the whole story.

The lesson: if a number controls deletion, make it defend itself. If it cannot, move the boundary back to query limits and keep the audit trail intact.

## 2026-08-20 - The Runtime History Learned To Take Out The Trash (Superseded)

The event bus had become Mission Control's nervous system, but its durable history had one classic control-room problem: the screens only showed the latest events, while the storage closet kept every old printout forever. Reading with a limit is not the same as retaining with a limit. It is like saying the desk is tidy because you only look at the top sheet while the filing cabinet slowly fills the hallway.

This pass briefly put a write-side cap on `SwiftDataRuntimeEventHistoryStore` so long-running operator sessions would not turn "recent history" into an unbounded local archive. That cap was later removed because it was not backed by a product retention policy, privacy decision, or ADR. The useful lesson survived, but the deletion policy did not: bounded reads are fine for UI; deleting audit history needs a real decision.

The lesson is a small but important shipping rule: observability needs retention policy, not just pretty filters. A timeline without pruning is a diary that never ends; a runtime foundation needs a logbook it can carry.

## 2026-08-20 - The Session Ledger Learned To Count The Model Bill

The runtime session model already knew where to put model names, token counts, and cost, but direct operator runs were still leaving those boxes mostly blank. The operator executor returned that telemetry on its artifact result, and Mission Control could infer some of it elsewhere, but the session itself was not swallowing the evidence. That is like printing the receipt at the register and forgetting to enter the sale in the ledger.

This pass moved the accounting to the governed pipeline boundary. When a tool executes successfully, the pipeline now records the artifact as before, then looks for the standard telemetry fields on the returned artifact and folds them into `AgentSession`: provider, model class, locality, prompt/completion tokens, estimated cost, and whether the counts were estimated. Tools that do not report model telemetry stay quiet instead of getting fake zeros dressed up as facts.

The lesson is that runtime foundations are only as trustworthy as their lowest-level bookkeeping. If a session claims to track models used and cost, that should be true at the same place execution becomes official, not reconstructed later by a lucky UI.

## 2026-08-20 - Mission Control Remembered Who Had The Keys

The runtime had learned to talk about context refreshes, memory touches, and capability leases, but two pieces still had the attention span of an open browser tab. Context instrumentation existed as host APIs, yet the shell refresh path could still update its snapshot without leaving a clear runtime breadcrumb. Capability leases were even more literal: relaunch the app, and the registry woke up empty. That is safer than accidentally keeping power forever, but it makes “temporary, inspectable, revocable” feel more like a sticky note than a control surface.

This pass gave both contracts a place to live. `ContextService` now accepts an instrumentation bridge and records every resolved shell context refresh with memory touches for account, chain, mode, balances, in-flight reuse, and local preference reads. The main tab wires that bridge to the shared persistent `RuntimeHost`, so production context refreshes now flow into the same session and event trail as planner and policy work.

Capability leases and restrictions also gained SwiftData-backed persistence. The registry hydrates from a store before answering grant or denial questions, persists grants, revocations, and restrictions as they change, and still treats expired or revoked authority as closed doors. The product promise is stronger now: after relaunch, Mission Control can inspect and revoke the authority it already granted instead of pretending the control room started from scratch.

The lesson is that orchestration is mostly accounting before it is intelligence. If an agent read context, write down what it touched. If an operator got temporary authority, store the key record and its expiration. Fancy autonomy can wait; the audit trail has to survive lunch.

## 2026-08-20 - The Runtime Got A Memory Instead Of A Megaphone

The Mission Control runtime already had a nervous system, but part of it behaved like a radio broadcast: if nobody was listening when an event happened, the signal disappeared. That is fine for a progress spinner and terrible for a control room. This pass gave the event bus a bounded durable history, backed by SwiftData in the persistent runtime host, so recent planner, policy, receipt, lease, approval, context, and memory events can come back after relaunch instead of living only in the moment.

Sessions also learned to close the book on successful governed tool runs. A direct tool execution now records its artifact and marks the session completed, while longer autopilot workflows still use their own terminal logic. Capability leases gained their shadow half too: explicit restrictions like “No wallet access” and “No external network” are now first-class, inspectable, and revocable, and they override matching grants before an approval prompt can hide the denial.

The last cleanup was context memory. The old pipeline guessed memory touches by looking for parameter names that smelled like `memory`. That is like calling every sticky note a database write because it has the word “file” on it. Runtime collaborators now have explicit APIs to record context refreshes and memory reads/writes by correlation ID, and the pipeline attaches those facts to the session and event feed.

The lesson is that orchestration foundations need boring facts, not vibes: a durable event, a terminal session state, a visible denial, and a named memory touch. Future agents can be fancy later; the audit trail has to be literal now.

## 2026-08-20 - The Approval Door Got Its Follow-Through

The runtime had finally made capability leases into real keys, but Mission Control was still walking users up to the door without handing them one. Operator buttons called the governed pipeline directly, which meant a perfectly allowed read-only operator could still bounce off the lease check. Approvals had a matching half-finished story: the console could record that a human approved a request, but the original proposal did not resume through the governed path. That is like getting a signed work order and then leaving it on the clipboard.

This pass connected the loop. Read-only operator runs now mint a short-lived, actor-and-session-scoped lease before they enter the pipeline. Approval resolution converts an approved request into the same scoped lease and reruns the exact proposal through registry resolution, deterministic checks, worklog, receipts, and the event bus with an approval-aware judge so it does not escalate forever. The app also stopped importing `RuntimeCore` directly just to satisfy a Mission Control public protocol; `MissionControlFeature` now re-exports the runtime types it exposes.

The lesson is that a safety gate is not complete when it can say no. It has to define the approved path too: who gets the key, what door it opens, how long it lasts, and what receipt proves the handoff happened.

## 2026-08-20 - Capability Leases Became Real Keys

The runtime used to hand itself a key at the same moment it wanted to open a door. Policy would say a tool call was allowed, the pipeline would mint a capability lease, and then execution would happen immediately. Mission Control could inspect and revoke leases, but revocation was more like taking away a souvenir keychain than changing the lock: the next allowed run could simply make a new lease.

This pass made leases authoritative. A governed tool now needs an already-active lease for the same capability, actor, and session before it can execute. The registry learned to answer scoped questions instead of global ones, expired leases now produce observable runtime events, and successful tool calls record artifacts and progress without automatically ending the whole agent session. That keeps sessions shaped like long-running work instead of one receipt-sized errand.

The lesson is that authority surfaces have to be boringly literal. A lease is not a badge the UI admires after the fact; it is the key checked at the door. If the wrong actor shows up, the wrong session asks, or the key has expired, the door stays closed.

## 2026-08-20 - Runtime Sessions Became The Logbook

The multi-agent runtime had good instruments, but a few of them were still clipboards sitting next to the machine. Workflows could emit events, receipts could prove outcomes, and Mission Control could derive a session-shaped story by reading the scattered evidence. That is useful, but it is not the same as having an actual logbook with a session's start, goal, powers, receipts, approvals, model use, cost, memory touches, artifacts, and end state written on the same page.

This pass made `AgentSession` the durable runtime object instead of a decorative struct. `RuntimeCore` now defines the session store contract and an in-memory implementation, `OperatorRuntimeStorage` persists sessions in the same SwiftData vault as worklogs and artifacts, and `RuntimeHost` wires the store through governed tool calls and autopilot runs. The event bus also learned the missing runtime vocabulary: planner, policy, session lifecycle, leases, receipts, context refreshes, and memory touches. Capability leases are now granted by real governed execution and revoked through the host, so the Mission Control UI is no longer staring at a registry that only tests knew how to fill.

The lesson is that observability needs an owner. Receipts are the signed artifacts, worklogs are the fine-grained trace, and events are the nervous system, but the session is the spine that lets future long-running agents stand up without pretending one-shot prompts are enough.

## 2026-08-20 - Mission Control Stopped Having A Side Office

The Settings shortcut had a trust-surface bug hiding in plain sight. The Ops tab opened the full Mission Control console with the shared persistent runtime host, but Settings opened a cozy little standalone home view backed by a brand-new `RuntimeHost`. That is like having the real control room downstairs and a duplicate dashboard upstairs with half the wires unplugged.

This pass made Settings use the same full Mission Control container as the Ops tab and pass through the active `ModeState`, so every doorway now lands on the same shared console: timeline, context, approvals, proposal diff, simulation, receipts, capabilities, mode, and all. The old fresh-host factory is gone, which removes the tempting footgun for future shortcuts.

The lesson is that trust UX cannot have alternate realities. A status surface is only trustworthy if every entry point reads the same runtime, the same mode, and the same audit trail.

## 2026-08-20 - Playbooks Got Shelf Space In The Artifact Room

The P1-500 readiness check found two almost-finished doorways. Manual playbooks could be installed, but the Routine Manager only invited scheduled, event, and maintenance triggers to the table. Meanwhile, artifacts could point back to playbooks, but the Artifact Browser did not show playbook definitions as browser objects. That is like building a control room where the recipe cards are in one cabinet and the finished reports are in another, then asking an operator to prove they belong to the same kitchen.

This pass made the visibility contract literal. Any installed or paused playbook now appears in the Routine Manager, including manual playbooks that run on demand after setup. The Artifact Browser also gained a Playbook objects section, with each definition linking back to the same authority-envelope detail view used by the Playbook Library. The browser now sees both the work products and the reusable contracts that produce them.

While retesting, an old playbook fixture tripped over the capability rename from camelCase to snake_case. The fix was not to rewrite history; `CapabilityID` now decodes through the legacy normalizer, so persisted playbooks that say `runPlugin` still land on today's `run_plugin` capability. Compatibility code is the little translator at the archive desk: it lets yesterday's records speak today's dialect without forging a new document.

The lesson is that "visible somewhere" is not the same as "visible where the acceptance criterion says to look." If a product promise names a room, put the object in that room, even if another hallway can eventually get there.

## 2026-08-20 - The Playbook Door Learned To Check IDs

The playbook install flow had a classic velvet-rope problem: the UI bouncer knew not to let execute-capable routines into v0, and the scheduler would refuse to run them later, but the model door in the middle would still stamp them as installed if someone called it directly. That is like locking the kitchen knives in the dining room while leaving the pantry key under the mat.

This pass moved the read/prepare rule into the Mission Control model boundary. Installing or resuming a playbook now checks the stored playbook contract first, returns a clear success flag, and leaves invalid execute-flow playbooks in their previous state. The routine QA checklist also gained automated witnesses: tests now cover install rejection, pause/resume behavior, run-now execution records and receipts, routine listing, and relaunch-style state/history hydration through shared stores, while the SwiftData storage test proves paused playbook state survives a fresh store actor.

The lesson is that UI guardrails are signs, not walls. A shipping automation system needs the wall at the state transition, because future buttons, deep links, migrations, and background workers will all find that doorway eventually.

## 2026-08-14 - Playbooks Got A Clipboard Before They Got A Megaphone

The playbook system had the bones of a routine library, but a few bones were still hiding in the UI's imagination. A playbook could imply read/prepare behavior because the default operator only made artifacts, and the library could show states, but it could not yet let a user author their own reusable routine. That is like calling something a cookbook while the chef is the only person allowed to write recipes.

This pass made the contract explicit. Playbooks now carry their source, v0 flow policy, required approvals, maintenance triggers, and backward-compatible decode defaults so older persisted records keep loading. Mission Control gained a user playbook editor, draft saving, edit support, and a review-before-enable sheet that shows scope, outputs, approvals, and authority before anything is installed. Background routine wiring now supplies event signals from runtime state, so event-triggered routines are not just labels on a shelf.

The lesson is that automation needs a clipboard phase. Before a system gets to run anything on a schedule, it should be able to say who wrote the routine, what it may touch, what it may produce, what approvals might appear, and where it stops. That turns "trust me" into a reviewable contract.

## 2026-08-14 - The Artifact Shelf Refused To Become A Card Table

The last readiness audit found a nasty kind of almost-safe behavior: if the dedicated operator runtime SwiftData container failed to open, `RuntimeHost.persistent` quietly built an in-memory runtime instead. That kept buttons from crashing, but it also meant artifacts could be created on a folding card table and disappear at relaunch while the UI looked perfectly confident.

This pass made the fallback fail-safe. A persistent runtime that cannot open durable storage now starts paused with a visible reason, and its artifact store refuses writes with a `RuntimePersistenceError` instead of pretending memory is a shelf. The app can still show Mission Control and explain what happened, but it will not mint work products it cannot keep.

The lesson is that durability features should fail loudly at the boundary where durability is lost. For artifacts, an unavailable vault is not an invitation to use a shoebox; it is a stop sign with a repair note taped to it.

## 2026-08-14 - Artifact Receipts Became Stored Relationships

The artifact system had a subtle audit wrinkle: operator-created artifacts could be linked from receipts, and the UI could reconstruct those links by reading receipt payloads, but the artifact record itself did not store the runtime receipt ID that proved its creation. That is like a museum catalog saying "see shipping manifest" instead of writing the manifest number on the object's own card.

This pass made the relationship explicit. `ArtifactStore` now has a receipt-linking operation, both the in-memory and SwiftData stores de-duplicate linked receipt IDs, and the runtime `ReceiptStoreSink` links the appended receipt back to the produced artifact after the receipt store returns its durable `ReceiptRecord.id`. The browser can still reconstruct relationships from payloads, but production artifacts now carry their own related receipt references too.

The lesson is that reconstruction is a convenience, not a contract. If an acceptance criterion says an artifact stores related receipts, the artifact should hold that edge directly, even if the UI has a clever fallback map.

## 2026-08-14 - Artifact Export Learned To Wait For The Handshake

Two artifact bugs were hiding in the gap between "looks shippable" and "survives real use." First, exported origin links could point at an older version after a newer artifact superseded it. The browser was correctly showing only the latest version, but the route resolver was using that same shelf as its whole library. That is like keeping archived contracts in the building and then telling reception only today's folder exists.

Mission Control now keeps a full artifact lookup by UUID while still browsing latest-by-group cards. Old exported links can walk back to their exact superseded version, and version loading refreshes that lookup too. The second fix moved the export receipt to the actual share completion callback. Preparing a file is not the same as shipping it; canceling a share sheet should not stamp `exported` on the artifact. The UI now prepares the provenance-rich file first, then records the exported lifecycle only after UIKit reports a completed activity.

The lesson is that audit systems live or die in the boring edges. A return address must resolve to the exact historical object, and a receipt should be printed when the courier takes the package, not when someone opens the packing table.

## 2026-08-14 - Artifact Exports Became Actual Files

The export button used to be a very well-dressed copy operation: it assembled provenance-rich text and handed that string to the share sheet. Useful, but not quite the same as giving another app a document, JSON file, or source file it can recognize.

This pass gave artifacts a real suitcase. Mission Control now writes a temporary export file with a type-aware filename and extension before opening the handoff UI: Markdown for docs, briefs, reports, and checklists; JSON for JSON exports; and source-flavored extensions for code files when the export format knows the language. The file still carries the Auralis origin URI and provenance block, so the handoff is durable without cutting the audit trail.

The lesson is that "share" and "export" are not synonyms. A share can be a sentence in someone else's clipboard; an export should be an object with a name, a format, and enough return address to find its way back into the system.

## 2026-08-14 — Artifact Origins Became Real Doorways

The artifact export system had learned to print a return address, but the address was only ink. `auralis://mission-control/artifacts/...` looked like a doorway back into Auralis, yet the deep-link parser and router did not know where that hallway was. That is the audit-trail version of labeling a button "Open" and wiring it to a sticky note.

This pass made the origin link a real route. Artifact deep links now parse through `AuralisShellCore`, route through the shell effect handler, select Mission Control, switch to the Artifacts section, and push the requested artifact detail after the store is loaded. Export and lifecycle controls also stopped swallowing persistence failures: approve, export, and supersede now require the artifact-store update and receipt append to succeed before the UI reports success or opens the share sheet.

The lesson is that provenance has to be executable where it claims to be executable. A receipt can describe the trail, but a product-grade origin link should walk the user back to the exact artifact, and a failed receipt write should be a visible stop sign instead of a quiet shrug.

## 2026-08-14 — The Export Button Got A Receipt Stamp

The artifact export flow had one last trapdoor: the share sheet could open without the artifact lifecycle moving to `exported`. That is like handing a package to a courier while the warehouse system still says it is sitting on the shelf. The user did the thing, but the audit trail did not necessarily know it.

This fix makes export one honest motion. Mission Control now uses a real export button that records the artifact export state and receipt first, then presents the share sheet from the recorded payload. The cached preview now updates from the post-export artifact too, so the exported text says `State: exported` and includes the Share sheet destination instead of narrating yesterday's draft.

The lesson is small but durable: when a UI action has audit meaning, the button cannot be decorative plumbing around a system control. The product action, the stored state, and the shared artifact have to leave the room together.

## 2026-08-14 — Artifacts Learned To Leave Footprints

The first artifact browser pass made the shelves usable, but export was still doing a magician's trick: the share sheet could hand off text, and then the system forgot the handoff ever happened. That is not an artifact lifecycle; that is a souvenir. A real work product needs a passport stamp when it is approved, exported, or superseded, because the whole promise of Mission Control is that important work does not vanish into a chat-shaped fog.

This pass wired the lifecycle all the way down. `ArtifactStore` can now persist state together with destination and export format, both the in-memory and SwiftData stores honor that contract, and Mission Control writes artifact receipts when the operator approves, records an export, or marks a version superseded. The browser also stopped peeking through the latest-100 mail slot: it hydrates the full artifact archive from the exported store data and reduces it to the latest version per group for browsing. Version comparison finally looks at actual content lines, not just character counts, so a changed checklist can point to the first changed line instead of shrugging with “different length.”

The practical lesson is that export is not a button; it is a state transition with evidence. The share payload is the package, the destination/format fields are the shipping label, and the receipt is the tracking number. Leave out any one of those and future-you gets to investigate a mystery.

## 2026-08-14 — Artifacts Got Real Shelves And Passport Stamps

The artifact system had the box and the label, but the browser still behaved like a storage closet: newest things in a pile, no way to ask for reports, this workflow, this account, or only recent work. That misses the whole point of an artifact. A work product is supposed to be found again by the reason it exists, not by luck and scrolling stamina.

This pass gave Mission Control's artifact shelf real facets: type, recency, workflow, and account. Cards now show provenance and state without making the user open every row like a mystery envelope. Detail views now carry the missing passport stamps too: destination, export format, source workflow links, related approvals, playbook links, and type-aware export payloads with an Auralis origin URI baked in. The model stayed stable; the browser learned to read the receipts, worklog, and playbook catalog around each artifact.

The lesson is that durable work products need handles, not just storage. If a report, checklist, JSON export, or code file leaves the app, it should carry enough provenance to walk back home. Otherwise "export" is just copy-paste wearing a tie.

## 2026-08-14 — Receipt Links Learned To Count Past One

The receipts epic had one of those almost-done traps: the UI could say "related artifacts," but one part of Mission Control was still reading the payload like there would only ever be one artifact ID, sitting politely at the top level. Real receipts are messier. They can carry arrays, nested objects, and reverse links from artifacts back to receipts. A browser that misses those relationships is not a browser; it is a peephole.

This pass gave Mission Control and the app receipt detail the same recursive artifact-ID reader. It walks receipt payload objects and arrays, follows keys that actually describe artifacts, preserves first-seen order, and removes duplicates so the detail screen can show all related artifacts without turning the raw payload into confetti. The acceptance routes also got explicit UI coverage for Approval Inbox -> Receipt Detail and Artifact Browser -> Receipt Detail, using seeded Mission Control fixtures instead of hoping a live operator session happens to be in the right state.

The useful lesson is that audit links are graph edges, not sticky notes. Once receipts become system objects, every doorway into them needs proof: browser, approval, artifact, summary, and whatever comes next. "Works from the main list" is table stakes, not ship readiness.

## 2026-08-13 — The App Receipt Drawer Got The Same Interpreter As The Control Room

The receipts epic had a split-brain problem. Mission Control had learned to read receipts like an operator needs them read: intent, plan, approvals, outputs, policy reasons, artifacts, capabilities, and postflight outcome. But the general app receipt detail still behaved like a filing cabinet with a flashlight: useful if you already knew which payload key mattered, not good enough if you were trying to answer “what happened?”

This pass gave the app-level receipt route its own human-readable receipt presentation layer. Home, Search, and the context inspector now land on a detail screen that starts with postflight, a readable audit story, a correlated timeline, related artifact IDs, and then the raw payload as the appendix. The lesson is that audit UX cannot depend on which doorway the user used. A receipt should tell the same story whether you arrived from the control room or from the hallway.

## 2026-08-13 — Receipt History Stopped Mixing Shelves

The receipt browser had two very different library problems. In the app timeline, receipts were filed by wallet but not by chain, so Ethereum and Base activity for the same address could end up on the same shelf. In Mission Control, search could only see the newest 500 receipts, which is like hiring a perfect librarian and then bricking up the back half of the archive.

This pass made receipt scope honest. App receipt lists and detail routes now treat chain as part of the scope whenever a receipt records one, while still allowing older chainless local receipts to show up. Mission Control's browser now hydrates from the full exported ledger and sorts it back into newest-first browsing order, with a fallback to the bounded latest window only if export fails.

The engineering lesson is that history features need two promises at once: the right room and the whole room. A searchable audit trail is not shippable if it answers from the wrong network, and it is not searchable if older facts silently disappear past an arbitrary window.

## 2026-08-13 — Receipts Learned To Speak Human

The receipt browser had the skeleton of an audit trail: a list, a search box, a detail screen, and links from the places operators naturally start. But the story inside each receipt was still too much like opening a shipping label and hoping it explains the package. Search only looked at the front of the envelope, postflight could call any successful receipt an artifact, and nested payloads were getting flattened into polite shrugs.

This pass taught Mission Control to interpret receipt payloads before presenting them. Browser search now includes the human-facing payload text, outcome filtering can separate success, denied, blocked, draft-only, no-change, and artifact-producing records, and receipt detail groups the audit material into requested intent, interpreted plan, approvals, actions, outputs, policy reasons, related capabilities, blocked/failure reasons, and what changed. The postflight classifier now treats plain successful control-plane receipts as no-ops unless the receipt actually records a draft or artifact.

The engineering lesson is that an audit surface is not done when the data is technically visible. Receipts need a reader, not just a drawer. The drawer keeps the immutable facts; the reader turns those facts into the sentence an operator needs before approving, investigating, or explaining what happened.

## 2026-08-13 — Approval Inbox Learned What “Done” Means

The approval inbox had a classic control-room problem: it could watch a request arrive, and it could write down an approve or reject decision, but a reload could resurrect the same request like the night shift never read the logbook. That is not an inbox; that is a sticky note with amnesia.

This pass made approval decisions durable in the receipt payload by recording the exact `approvalID`, then filtering approved and rejected requests during worklog hydration. Deferred approvals still come back, because “later” is not “done.” Capability leases also grew explicit authority metadata: a reason and one of the account, data, execution, or artifact scopes. The inspector can now show what was granted, why it was granted, how long it lasts, and where that power applies instead of reverse-engineering authority from a raw capability string.

The engineering lesson is simple: user-facing authority surfaces need state that survives the happy path. A receipt is not just proof for an audit export; it is also the console’s memory of what the operator already decided.

## 2026-08-13 — Assist And Operate Stopped Wearing Observe Receipts

The mode switch worked, but parts of the audit trail were still signing the guestbook as Observe no matter which badge the operator had on. That is the kind of bug that does not break a button, but it breaks trust: a receipt is supposed to explain what authority was active when work happened.

This pass made governed runtime receipts mode-aware, including tool outcomes and routine runs. Background runtime now restores the persisted mode instead of silently building an Observe-only host. Account and ENS receipt recorders also accept an active-mode provider, so shell, gateway, profile, and resolver paths can stamp receipts with the mode the user actually selected. The package-level policy gate service learned to accept execution evidence and signing allowlists, which keeps package tests and fallback adapters from becoming deny-all traps while the app itself routes policy decisions through the unified runtime pipeline.

The bigger lesson is that a mode rollout is not just an enum and a picker. The receipts, background jobs, docs, comments, tests, and stray profile copy all have to tell the same story. Otherwise the app becomes that office where the door sign says "Operations" but every form still says "Observation Desk."

## 2026-08-13 — Mission Control Learned To Show The Whole Flight Board

The console was no longer empty, but the snapshot camera was still taking pictures of the quietest room. Timeline and Activity had smart logic behind them, yet the visual baselines only proved the empty state. That is like testing an airport board at 3 a.m. and declaring rush hour solved.

This pass gave Mission Control populated snapshot fixtures for queued, running, waiting, blocked, completed, and failed workflows. The timeline now has a visual proof set for stop buttons, account filters, playbook labels, and next-step copy. The activity feed gets grouped high-signal events with observation, preparation, approval-needed, and completed categories on screen. Mode snapshots also cover Assist and Operate, and the surface now calls those modes approval-gated and evidence-gated instead of lazily calling everything "Available."

The useful product rule is honesty under bright lights. If Assist and Operate are visible, the UI and docs must say what actually makes them safe: approvals, deterministic evidence, confirmation, and receipts. A management console should never make authority sound like a magic door.

## 2026-08-13 — Mission Control Got A Brake And A Real Mode Switch

The P1-101 checklist had one word that mattered more than it looked: "stop." A global pause switch is useful, and revoke controls matter, but neither one lets an operator point at one workflow and say, "that one, stop that one." Today Mission Control got that brake pedal. Timeline rows for queued, running, and waiting workflows now show a Stop control; pressing it writes a durable stopped receipt, records a terminal blocked worklog entry, emits a runtime event, clears matching pending approvals, and reloads the console state. It is not pretending to cancel an invisible task registry that does not exist yet; it stops the workflow at the control-plane level this runtime actually owns.

The mode switch also graduated from wall art to machinery. `CryptoMode` now has Observe, Assist, and Operate cases, `ModeState` persists real selections, and the shared `RuntimeHost` reads and writes the same mode state the rest of the app uses. Mission Control's Mode surface is now a native picker instead of a hard-coded Observe label. The governance rules stay deliberately sober: Observe blocks crypto, Assist escalates crypto proposals, and Operate still runs through policy evidence and confirmation rules instead of becoming a secret signing shortcut.

The design lesson is the same one airport control towers understand: labels are not controls. A console becomes trustworthy when the button changes the same state the engine reads, and when the logbook can explain what happened after someone pressed it.

## 2026-08-13 — Mission Control Stopped Being Almost A Console

The P1-100 review found the uncomfortable kind of gap: the console existed, but the acceptance checklist could still poke fingers through it. Workflow state only had four buckets, so "queued" and "failed" were getting flattened into nearby shapes. Timeline filters could narrow by status, but not by the account or playbook an operator actually cares about. The Activity Feed had signal, but not enough structure: related work needed grouping, events needed category labels, and receipt-backed events needed a path to the receipt instead of a dead-end row.

Today's hardening pass turned those promises into code. Mission Control now derives queued, running, waiting, blocked, completed, and failed from the durable worklog; the home console shows all of those counts plus context freshness and revoke controls. Timeline rows carry account and playbook facets with filters for both. Activity groups related session events, labels them as observation, preparation, approval-needed, or completed, and links to receipt detail when a matching receipt exists. Mode is no longer just a sentence about Observe: Observe, Assist, and Operate each have a visible surface, with Assist and Operate clearly gated until policy authority exists.

The lesson is a management-console lesson, not just a UI lesson. Operators do not need a prettier chat transcript; they need a board that answers "what is waiting, who owns it, what can I stop, and what proof exists?" The focused MissionControlFeature unit suite now pins those derivations. The app builds green; the full package snapshot lane still crashes in this managed CLI environment inside SnapshotTesting's AppKit image path, so visual baselines should be rerun from a healthy Xcode snapshot environment.

## 2026-08-12 — Mission Control Got Durable Memory

The first Mission Control pass could watch work while the app was awake, but too much of the operator console still behaved like a whiteboard after closing time: artifacts lived in memory, worklog events rode the live bus, and approvals produced receipts without making the continuation story explicit. Today's patch moved the console closer to a real control room. Artifacts and worklog steps now have SwiftData-backed stores, the runtime host wires those stores into the governed pipeline, and Mission Control can hydrate timelines from durable worklog history after relaunch instead of pretending the live event stream is history.

The other lesson was naming honesty. “Approve” sounds like an engine will resume the original work; this version records the approval decision as an auditable decision packet until continuation is explicitly implemented through the governed pipeline. Scheduled routines also stopped using pretend freshness signals: last-run time now comes from persisted execution records, and event triggers only fire when real signals are present. The product can still be scaffolded, but the UI now has to say what is actually true.

## 2026-08-11 — Playlist Helpers Left The Old Engine Hallway

The last code living under `MusicApp/AI/Audio Engine/` turned out not to be an audio engine at all. It was the app-owned playlist helper stack: creation/update/delete helpers, the list/create SwiftUI views, and the playlist privacy note. Those files moved to `MusicApp/AuraPlay/Playlist/`, and the now-empty `MusicApp/AI/` group was removed.

The cleanup rule stayed deliberately precise: keep playlist capability, remove legacy ownership confusion. `MusicFeature` already owns the AuraPlay playlist model and service; these app-owned helpers remain only where primary-store receipt behavior still needs an app adapter. The remaining work is proof and convergence, not folder archaeology.

## 2026-08-11 — The Old Engine Signposts Came Down

The code had already moved farther than the docs admitted. The app-local `AudioEngine.swift` is gone, the Music tab enters through `MusicFeatureRootView`, audio runs through `AuraPlayAudioEngine`, and video runs through `AuraPlayVideoEngine`. Some docs were still pointing at `AI/V1`, `AuraPlayTabRootView`, and the deleted app engine like old road signs after the bridge was replaced.

The cleanup rule we wrote down was deliberately precise: keep playlist capability, remove legacy ownership confusion. `MusicFeature` already owned the real AuraPlay playlist model and service, while a few playlist helpers still sat under `MusicApp/AI/Audio Engine/Playlist/`. That note became the handoff for the follow-up move rather than permission to delete playlists.

## 2026-08-11 — Wallet Support Got A Proof List

Wallet compatibility is the kind of feature that sounds real the moment a logo appears in a picker, but a logo is not a handshake. Today the docs got a hard support-proof list: Rabby, Rainbow, Coinbase Wallet, MetaMask, Phantom, Backpack, Solflare, Privy, and Dynamic. Each route has to prove the boring-but-essential loop on a physical device: connect, reject or cancel, prove ownership, disconnect, restore or fail closed, and come back through the callback path exactly once.

The useful product lesson is restraint. Auralis can compile wallet adapters and still not truthfully claim production support until a real wallet app, a real device, and a real account have all taken the same path a user will take. The QA docs now make that visible in the P0 device suite, the AuraPlay physical-device suite, Phase 14 master QA, App Review, known limitations, status, gaps, and future-work maps.

## 2026-08-11 — Phase 5 Moved From Handoff To House Map

The Phase 5 handoff had become a time capsule. It still talked about Alchemy as partial, the coordinator as adjacent, artwork prefetch as not started, and integration tests as missing. The code told a different story: `AlchemyNFTClient`, `HeliusNFTClient`, `MetadataFetcher`, `MetadataParser`, `MediaClassifier`, `NFTSyncCoordinator`, `MediaItemArtworkPrefetcher`, and the Phase 5 integration suite all live in `MusicFeature`. The handoff had done its job; keeping it around was like leaving construction tape across a door people already use every day.

So the durable facts moved into the house map: `AuraPlay-Status.md` now records the implemented discovery pipeline and its tests, `AuraPlay-Implementation-Plan-Completed-Phases.md` carries the compact completed summary, `AuraPlay-Gaps.md` keeps the real remaining validation and organization gaps, and `AuraPlay-Future-Work.md` is back to future work instead of yesterday's implementation checklist. The only thing we could not prove fresh today was the package lane itself, because the managed environment could not write SwiftPM/DerivedData state and CoreSimulator was unavailable. That is an infrastructure note, not a reason to pretend Phase 5 is still waiting for a client that already exists.

## 2026-08-11 — Phase 3 Closed Its Filing Cabinet

The Phase 3 storage-resolution tickets had already done their job: `URLResolver`, `URIScheme`, `GatewayFallbackChain`, the configuration value, the error case, and live `MusicAssembly` wiring are all still in the codebase. The extra follow-up file was really tracking unrelated package-test debt, so today we moved that debt into the general maps where it belongs: `AuraPlay-Gaps.md`, `AuraPlay-Future-Work.md`, and TEST-015.

The little archaeology dig mattered. Some old warnings had fossilized after the code moved on — ProviderKit now expects redacted payloads, ChainProviders imports the shared lock helper, AccountStorage sees the moved primary models, AuraUI's color tests no longer carry the bad macro shape, and the SwiftData storage test types are already main-actor isolated. The remaining suspects are narrower: ENS still has duplicate binding / throwing-signature cleanup, NFTLibraryFeature has response shadowing and a couple of nested Swift Testing macro patterns, and the package-test lane itself still needs a clean environment. Today's attempt could not prove the lane because CoreSimulator was unhealthy and the managed sandbox blocked SwiftPM manifest/cache writes. That is the lesson: close the phase, keep the debt, but put each card in the drawer that future engineers will actually open.

## 2026-07-26 — WalletConnect Got A Real Front Door, But Not The Whole House Yet

Phase 4 moved from paper architecture into the app shell today. `WalletConnectorKit` is now linked into the Auralis app target, AuraPlay's wallet button opens a dedicated WalletConnect picker instead of the generic account switcher, and the app has a SwiftData adapter that turns approved WalletConnect addresses into wallet-backed `EOAccount` rows. The picker has provider buttons, a generic QR pairing path, Keychain topic storage through the clean-room package, active-wallet selection, removal affordances, and accessibility identifiers for the controls UI tests will need.

The useful architectural line is the same one we kept drawing in the docs: the app owns UIKit, SwiftData, and presentation; `WalletConnectorKit` owns CAIP parsing, provider catalogues, pairing URI construction, relay transport boundaries, and session lifecycle rules. Think of it like adding a new front desk without moving the safe into the lobby. Private keys still never enter the building, session topics go through Keychain with device-only unlocked storage, and the UI only asks the package for connection events.

The honest caveat matters: this is not yet a shippable full WalletConnect v2 implementation. The clean-room relay can create and subscribe a real IRN pairing URI, and the app can deep-link or show the QR payload, but encrypted session proposal publication and `wc_sessionSettle` approval decoding still need to be completed before a real wallet can approve and persist a live session end-to-end. Today's green build and `Auralis-Fast` run prove the app is wired without breaking the rest of Auralis; they do not prove the real-wallet approval handshake is complete.

## 2026-07-25 — AuraPlay Playlists Stopped Asking The Wrong Pantry

The crash looked like a CoreData SQL tantrum: `AuraPlayPlaylistItem` and `AuraPlayPlaylist` were "not a valid entity name" during a SwiftData change request. The real mistake was quieter. `LibraryRootView` had one `@Query` pointed at primary-store accounts and another pointed at AuraPlay playlists. SwiftUI gives a view one model-container environment, so the playlist query eventually knocked on the primary store's door and asked for tables that live in the AuraPlay pantry.

The fix was to stop making the view carry live playlist models at all. `AuraPlayPlaylistService` now hands the UI small Sendable playlist snapshots, and playlist mutations reload those snapshots explicitly. It is the same lesson with a fresh sticker: SwiftData models are excellent inside their store and actor, but the moment a UI needs data from two stores, plain values beat clever environment gymnastics.

## 2026-07-25 — Phase 13 Learned To Match The Ticket's Vocabulary

Two ship-review caveats got tightened without throwing away the working shelves. Smart Resume still uses the explicit SwiftData tombstone row, because that is the right local recovery mechanism for AuraPlay, but the code now names the contract out loud: `AuraPlayPersistentHistoryPlaybackTombstone`, a token identity value, and a shared recency policy. It is a bit like labeling the filing cabinet instead of buying a new cabinet; the record is the same, but now the acceptance checklist can find the drawer.

The embedding gate also got less chatty. Settings remains the one place that explains unavailable smart playlist features, while the Library simply omits Playlist Playground when embeddings are unresolved or unavailable. That matches the product rule better: unavailable intelligence should be a quiet missing doorway, not a signpost in every hallway.

## 2026-07-25 — Phase 13 Got Its Boarding Pass Stamped

The earlier Phase 13 work had the features, but the acceptance desk still wanted better paperwork. Today’s pass moved the proof into the lane Xcode actually runs: `Auralis-Fast` now discovers the app-hosted Phase 13 suite, and the suite carries a process-wide URL-loading trap around Playlist Playground plus More Like This. If those paths try to sneak out to HTTP while ranking, the test records the request and fails. The important bit is not that the trap is dramatic; it is that the smart features are now pinned to local semantic search, SwiftData rows, and deterministic fixtures.

The More Like This menu also got a sharper contract. The UI already used a cached set of media IDs with stored embeddings, but now `AuraPlayRootModel` has tests proving the context-menu gate is per item, scoped by account and chain, and cleared when the shell scope changes. When embeddings are globally unavailable, the model does not even ask for item IDs. That keeps the feature honest: a track earns the sparkle button because it has a local vector, not because the device vaguely supports embeddings somewhere.

The final hardening pass replaced the last "looks smart because it sorts nicely" shortcuts with behavior that matches the ticket. Playlist Playground now samples from the semantic candidate pool with deterministic weighted randomness instead of slicing off the top five, More Like This tries the strict 0.72 threshold before relaxing to 0.60 only for sparse result sets, and Smart Shuffle has a large seeded trial plus runtime checks for plain-shuffle fallback and repeat-all reseeding. The one piece that remains intentionally outside local proof is the five-consecutive-CI-runs gate; that needs CI history, not a heroic single-machine sprint.

## 2026-07-23 — Phase 13 Ship Sweep: Closing The Honest-Inputs Gaps

The July 20 entry ended on the right warning: Smart Shuffle "cannot promise play-count weighting until playback history actually records play counts." This pass made the record clerk actually file the cards. `AuraPlayPlaybackPositionState` now persists `playCount`, `markCompleted` increments it, `playbackHistories()` threads it through, and the Smart Resume tombstone carries it so a returned token keeps its play history. The `1 / (playCount + 1)` term in `SmartShuffleWeighting` was dead code weighting nothing; now it bites, and the test proves more plays means a strictly lower weight.

Two smaller ecosystem splinters came out too. The collection-share link could double-prefix the chain (`chain|chain|contract`) whenever a group had no contract address, because the share builder handed over the composite `group.id` and the handler prefixed the chain again. The builder now emits a bare identifier and the handler refuses to re-qualify an already-qualified one — belt and suspenders, with a round-trip test. And More Like This got a "Save as Playlist" action that reuses the exact Playlist Playground materialization path, so a good recommendation set can become a smart playlist without a second code path.

Two items were resolved by decision rather than code: silent-drop of unparseable deep links is intended product behavior (tests already assert it), and hiding More Like This per-item when the source lacks an embedding stays a graceful empty state instead of a costly per-render async probe. The app target builds green; the package-test lane is the last gate. The gap log now reads as closed for Phase 12/13 except the honestly-deferred follow-ups.

## 2026-07-20 — Phase 13 Got Its First Real Smart Shelves

Phase 13 moved from corrected plan to working foundation today. The smart features now enter through real AuraPlay seams instead of imaginary ones: embedding availability is an injected cached provider, Playlist Playground uses `AuraPlaySemanticSearching` plus `AuraPlayPlaylist.isSmart` and `smartQueryData`, More Like This compares persisted `AuraPlayMediaEmbedding` vectors, and Smart Shuffle is a pure weighting strategy that can be tested without waking the playback engines.

The most important implementation lesson was Smart Resume. The old ticket wanted Persistent History tombstones, but this codebase did not have that machinery, so we gave AuraPlay its own small tombstone shelf: `AuraPlayPlaybackPositionTombstone`. When sync reconciliation removes a playable media row, resumable progress gets filed by wallet, chain, contract, and token ID. If the same on-chain token returns under a new media row, the position is restored. That is the right kind of intelligence for a wallet music app: exact identity, no guessing, no spooky content matching.

The UI slice is intentionally narrow. Playlist Playground lives in the existing AuraPlay Search segment and says plainly that generation happens on this device from the local library. More Like This sits in item context menus when embeddings are available and reuses the same `LibraryItemCell` family in its result sheet. The verification pass built the app and test targets, and the focused app tests for schema/search/embedding still pass. The new package-level Phase 13 tests are written, but the direct `xcodebuild test -scheme MusicFeature -destination platform=macOS` run was killed after CoreSimulatorService went unavailable in the command-line environment, so those need a clean package-test lane run next.

## 2026-07-20 — Phase 13 Put The Smart Stuff On The Existing Shelves

The first Phase 13 intelligence draft had the right instinct — keep it on-device and avoid cloud magic — but it was still wearing an older map of AuraPlay. It talked about a generic `SearchService`, `MediaItem`, `Playlist.aiGenerated`, and Persistent History tombstones that the current code simply does not have. The updated plan now starts from the shelves that actually exist: `AuraPlaySemanticSearching`, `AuraPlayEmbeddingService`, `AuraPlayMediaEmbedding`, `AuraPlaySearchCoordinator`, `AuraPlayPlaylist.isSmart`, `smartQueryData`, `AuraPlayPlaybackPositionState`, and the Phase 8/10 queue contracts.

The useful planning lesson is that "AI-adjacent" features are only cheap when they are honest about their inputs. Playlist Playground can be a thin layer over semantic search. More Like This can compare stored vectors. Smart Resume, however, cannot pretend a tombstone identity record exists; it needs a small explicit AuraPlay recovery contract. Smart Shuffle also cannot promise play-count weighting until playback history actually records play counts. Intelligence is less like a wizard and more like a very organized record clerk: it can only make good suggestions from the cards we actually filed.

## 2026-07-20 — Phase 12 Stopped Asking Yesterday's App For Directions

The ecosystem plan looked tidy until it met the current codebase. It was still talking about a future `ChainRegistry`, a fictional `AppRouter.handle(url:)`, and a generic `MediaItemService` that could somehow hop across wallets. Auralis already has the real machinery: `AuraPlayExplorerURLBuilder` backed by `ExplorerAdapter`, `AuraPlayPlayerContextActionHandler` for share/Safari/pasteboard work, `LibraryRootView` and `LibraryGroupDetailView` for music navigation, and deep links that enter through `AppDeepLinkParser` and `ShellStore` before the router ever changes tabs.

The updated Phase 12 map now follows those roads. Provenance hardens the metadata we already persist on `AuraPlayMediaItem`. Sharing reuses the existing UIKit action seam instead of sprinkling `ShareLink` policy through views. Creator aggregation gets called out as the one intentional cross-wallet exception, because today's `AuraPlayLibraryScope` is account-and-chain scoped by design. And ADR-007 makes the link story honest: v1 uses the already-declared `auraplay://` scheme; HTTPS universal links wait until someone owns and serves a real AASA file. Deep links are like street signs: if you print signs for roads nobody built, users still get lost.

The implementation pass turned that map into working code. `AuraPlaySharePolicy` now centralizes media, playlist, collection, and creator share payloads so tracking parameters do not sneak in through a random button. `ProvenancePanelView` gives the context menus a real on-chain facts sheet without importing UIKit or explorer policy into `MusicFeature`. Creator profiles now have a named cross-wallet query instead of abusing a nil account scope, which is the important distinction: a special door should have a sign, not a loose hinge. Deep links now parse `auraplay://playlist`, `auraplay://collection`, and `auraplay://creator` through the existing shell. Playlist links honestly show the v1 local-device limitation when the target is not available.

The hardening pass caught the difference between "routes somewhere" and "lands kindly." A shared collection link can point at media the recipient does not own locally, which is normal for a read-only wallet library, not an error. The collection detail screen now says that plainly instead of handing the user an empty list with no explanation. Explorer coverage also moved from "the adapter probably knows" to a Phase 12 contract: Ethereum, Base, Arbitrum, Optimism, Polygon, and Solana each have an asserted AuraPlay provenance URL. That test is the passport stamp for the whole sharing story.

The final polish pass caught three places where the ecosystem door opened only halfway. Playlist links already knew how to become `.playlist(id:)`, but the shell-level music route always showed the "not on this device" fallback, even when the playlist was sitting right there in the AuraPlay store. The fix was not to query playlists from the app's primary SwiftData container like a lost tourist; the route view installs the AuraPlay container and resolves the local playlist where that model actually lives. Creator rows now share their `auraplay://creator/...` links from the visible UI, and the provenance sheet gives copy feedback inside the sheet itself, with haptics and an accessibility announcement. Tiny lesson, familiar tune: routing, storage, and feedback all need to meet in the same room before a feature feels complete.

The acceptance sweep found two last Phase 12 splinters. First, shell-level creator links were walking into a painted-on empty state while the real cross-wallet `CreatorProfileView` lived one room over inside the library stack. A new public route wrapper now lets the app router enter the same creator profile machinery the library uses, with all connected wallet addresses passed in deliberately. Second, malformed links now get a quiet warning log instead of a modal scolding. Deep links are invitations, not subpoenas; if the envelope is nonsense, the app should shrug, log it, and keep the room calm.

One more collection-route mismatch tried to sneak through by wearing a familiar name tag. `auraplay://collection/...` links were parsed correctly, then handed to the old `MusicLibraryItem` collection detail view, which groups by a normalized collection-name key. AuraPlay's real media store groups collections by `chain|contract-or-key`, so a perfectly valid shared link could arrive at the right tab and still stare at an empty room. The fix was to route app-level collection destinations through a public `AuraPlayCollectionRouteView`, the same media-store loader used inside the library stack, and to preserve the grouped key when opening collections from rows or item details. The new round-trip test is the bouncer: generate a collection share link, parse it, route it, and make sure the key still says `base-mainnet|0xabc`.

## 2026-07-19 — The Dark iOS-27 Search Stages Got Honest Wiring

The assistant's custom pipeline stages were the part of search nobody could actually watch run, because the whole path is gated to iOS 27 and Apple Intelligence. That is exactly where fragile code likes to hide. This pass replaced the guesswork with the structured Spotlight tokens the indexer already emits: `AuralisMediaCapabilityStage` now scores off `mediaKind`, `isPlayable`, `artistName`, and `collectionName` with named weight constants instead of scanning free text for the word "music", and `AuralisReceiptRollupStage` reads its grouping value straight from the tokens instead of parsing "Trigger: …" out of a sentence. The table view stopped string-stripping `.string(...)` syntax off cells; the typed `SearchResultsTable.Value` is now pattern-matched at the source.

The useful catch was a latent bug the string fallbacks were papering over: chain grouping looked up a `receiptChain` token that the indexer never writes, so it *always* fell through to the free-text parser. Chain is a shared token, not a receipt-scoped one. Once the stages trusted structured data, the bug had nowhere to hide. The lesson repeats: a "defensive" fallback is often just a bug wearing a raincoat — it keeps the wrong answer from ever surfacing as a crash.

Unit tests now pin the structured-token contract in `SearchAssistantStageTests`, including a regression for the chain lookup. Then the lights actually came on: run against a physical iOS 27.0 device, all 11 stage/cell/evaluation-seed tests pass, the pre-existing `SearchSpotlightSupportTests` stage tests still pass, and the on-device model reports `.available`. Getting onto the device meant fixing an unrelated device-build breakage first — the vendored `CodeScanner` referenced its simulator-only `sendSimulatedCode()` from an unguarded selector, so every device build failed to link. The one dark corner still dark: the evaluation only scores a fixture stub, not the live `SearchAssistantService` pipeline. The model is available and the path runs, so that is now real follow-up work, not a runtime blocker — deferred deliberately because a live-LLM plus async Spotlight evaluation does not belong in the fast lane without its own harness.

A pre-commit review of the Phase 11 search work found the tree built locally only because three needed files were still untracked — most importantly the entire AuraPlay search domain (`AuraPlaySearch.swift`), which the library and root views depend on. The fix was staging discipline, not code: move tracked and untracked together so a partial commit cannot ship a broken tree. The lesson is old but keeps knocking: a green local build says nothing about what git actually captured.

The review also caught the seams left by the `.searchable` migration. `SearchInputCard` and `SearchSuggestionsCard` were the custom counter we no longer stand behind now that the OS owns the field, so they came out. And the marquee assistant, gated to iOS 27 because the SDK marks `SpotlightSearchTool` that way, was quietly advertising itself: on the current OS every empty text search showed a "requires iOS 27" upsell instead of an honest "no local matches." Presentation now consults real availability, so the feature stays dark until it can actually work. Do not sell a door that does not open yet.

## 2026-07-19 — Search Moved Into The System Search Booth

The WWDC search overhaul was the moment Auralis stopped treating search like a custom console wearing a magnifying-glass hat. The global Search tab still owns the big cross-app question — wallets, ENS names, contracts, NFTs, ERC-20s, receipts, and AuraPlay — but the field itself now belongs to SwiftUI's native `.searchable` machinery. That hands keyboard focus, clear/cancel behavior, platform placement, and future system styling back to the operating system, which is exactly where users expect those tiny habits to live.

The new split is visible scopes for broad, obvious filtering and search tokens for power moves. The scope bar is the labeled aisle sign: All, NFTs, Tokens, Music, Receipts, Accounts. Tokens are the little basket dividers inside the search field: content type, media traits, account, and chain. Keeping both matters because tokens are fast once discovered, but a visible scope bar is the friendly employee pointing at the right shelf.

Under the counter, suggestions learned to rank like a person thinks. Prefix matches beat word-prefix matches, word-prefix beats substring, and recents/current scope get a small boost. That is not fancy AI; it is good manners. Large wallets make this lesson obvious: before asking the assistant to reason, build a local index that can find the obvious thing quickly and predictably.

## 2026-07-19 — Search Put The Magnifying Glass Back On The Counter

The Apple search design session was a good reminder that search is not just a text box with ambition. People bring years of muscle memory to that little magnifying glass: type, clear, cancel, see recents, narrow the room, and get a useful miss instead of a blank wall. Auralis already had the smart back room — local indexing, Spotlight donation, assistant grounding — but the front counter still felt like a custom command console.

This pass keeps the Aura-styled surface but gives it the expected search manners. The field now wears the universal search icon, has a real clear button, keeps Cancel as a non-destructive keyboard dismiss, and exposes scopes for All, NFTs, Tokens, Music, Receipts, and Accounts. Prefix suggestions now come straight from the local index, so token symbols, NFT names, collections, ENS/account labels, and other indexed handles can shorten the user's typing without waiting for the assistant.

The useful product lesson is that intelligence should not be the first thing users have to wait for. Exact local matches, scopes, recents, suggestions, and honest empty states are the fast counter. The LLM assistant is the specialist behind it, not the cashier for every banana. When search feels shippable, it is usually because the ordinary paths are boringly good before the fancy paths start talking.

## 2026-07-19 — Search Learned To Ask With Receipts In Hand

The WWDC Core Spotlight search pass turned Auralis search into a two-counter setup. Exact crypto inputs still go to the fast counter: wallet addresses, ENS names, and invalid safety cases stay deterministic because nobody wants a language model improvising with a contract address. Product questions get the richer counter now: local token, NFT, collection, receipt, and AuraPlay matches can still appear immediately, while the assistant can read from the same Spotlight shelf and add grounded context when the OS supports it.

The useful catch was an SDK calendar trap. The session talks about `SpotlightSearchTool` as the shiny new assistant bridge, but this local SDK still marks the tool APIs as iOS 27 while the app deploys to iOS 26. The implementation keeps the library cards useful today by indexing through Core Spotlight, and gates the LLM assistant behind availability so exact search does not trip over a future-only feature. Search is now a librarian with two desks: one for barcodes, one for questions.

The WWDC lesson that stuck hardest was metadata quality. Auralis now gives Spotlight more than a title and a blob of keywords: documents carry chain, account, contract, token standard, artist, collection, media kind, receipt status, dates, and model-only hydration notes. Hydration is the librarian pulling the full folder from the back room after the index card gets you to the right shelf.

The assistant UI also stopped pretending every answer is just a flat list. Spotlight replies can arrive in multiple queries and stages, so Auralis now keeps sections for item lists, scored items, grouped items, counts, tables, statistics, and text. Custom pipeline stages give the model two app-native calculators: one that scores playable media traits, and one that rolls receipts up by status, trigger, chain, or scope. The evaluation seed is deliberately small, but it puts a ruler on the table: result coverage has to stay measurable instead of being judged by vibes.

## 2026-07-18 — Phase 11 Search Got Its Boarding Pass Checked

The Phase 11 search review had one last trap: an older April ticket sheet kept asking for a grand `SearchService`, a separate integration target, and a Spotlight-first tier show. The app had already taken a cleaner route. AuraPlay search now lives where users actually touch it, inside the Music tab's Library Search segment, with local matches first, semantic matches merged in, scoped recents, and the visible result set handed to playback as the queue.

The hardening pass turned that from "looks implemented" into something easier to defend. The active `Auralis-Fast` test plan already includes the app-hosted AuraPlay search tests, so we kept that lane instead of creating a ceremonial target. Semantic search already checked cancellation while scanning persisted items; now a regression test pins that behavior so a cancelled search cannot wander back from the kitchen with yesterday's order. The lesson is a good shipping rule: do not build the old map just because someone found it in a drawer, but do write down why the current road is the one we are driving.

## 2026-07-18 — Phase 11 Search Became A Real Counter

AuraPlay search moved from ticket plan to working surface today. The Search segment now has a live field, library-backed suggestions, scoped recent queries, natural-language examples, local-plus-semantic merged results, filters that reuse `MediaItemFilter`, and a tap-to-play path that seeds playback from the visible search result set instead of throwing the whole library at the engine.

The useful engineering move was treating search as a coordinator, not a decoration on the text field. Local matches arrive immediately, semantic matches can follow later, and each submitted query carries a generation token so a slow old search cannot stroll back in and overwrite the newer one. The result is the same lesson playback already taught us: async features need a bouncer at the door, especially when users type faster than background work completes.

Coverage now lives where Xcode actually runs it: `AuraPlaySearchTests` in the app test plan cover autocomplete, semantic merge, stale-query cancellation, post-merge filters, recent-search dedupe, empty-query behavior, and search-origin playback windows. The package scheme still reports zero tests, so the honest CI route remains app-hosted Swift Testing until that scheme grows a real package test action.

## 2026-07-18 — Phase 11 Search Stopped Pretending The Room Was Empty

The first Phase 11 Search ticket set assumed AuraPlay was still waiting for a brand-new three-tier `SearchService`. The code had moved on. Global app search already handles wallets, ENS, ERC-20s, NFT tokens, and collections, while AuraPlay already owns media-specific pieces: library text filtering, `MediaItemFilter`, reusable library cells, Spotlight indexing, and semantic search through `AuraPlayEmbeddingService`.

The updated plan keeps those lanes separate. Global search remains the building directory; AuraPlay search becomes the record-store clerk who knows tracks, artists, collections, playback, and weird natural-language moods. The tickets now improve what exists: autocomplete from active library data, merged local-plus-semantic result presentation, scoped recents, shared filters, and mocked integration tests. The useful lesson is planning hygiene: tickets are maps, not fossils. When the terrain changes, update the map before sending engineers into yesterday's hallway.

## 2026-07-17 — Helius Learned To Ask For The Right Shelf

The Solana NFT path needed the right amount of ambition. Helius says `searchAssets` is the power tool for filtered discovery, but a plain wallet gallery still belongs on `getAssetsByOwner`. Both the app inventory provider and AuraPlay discovery now use that endpoint for wallet-owned NFTs, explicitly keep fungibles out, and ask for collection metadata plus unverified collection grouping so the library does not silently miss the oddball records users actually care about.

The other trap was the JSON-RPC envelope. Helius can return HTTP 200 with an `error` payload, which means "the cashier said no" can look like "the door opened" unless we check the receipt. The clients now decode RPC errors, map auth and rate-limit failures into typed app errors, and tolerate missing collection grouping instead of dropping the whole response on the floor. Provider APIs are restaurants, not vending machines: sometimes the plate comes back with a note, and the code has to read it.

The follow-up docs also caught a useful performance wrinkle: `total` belongs with `showGrandTotal`, and that flag is slower. Pagination now walks until Helius returns a short page instead of paying for a grand-total headcount on every shelf check.

The robustness pass added one more Helius lesson: not every empty shelf is a broken shelf. The DAS docs list 404 as "no assets found" for owner queries, so Auralis now treats that as an empty wallet instead of a provider outage. Rate limits also got a proper traffic light: both Helius paths retry transient 429/server responses, and the shared inventory provider respects `Retry-After` through the existing parser that understands numeric seconds and HTTP-date headers. The API is basically saying, "come back after the kitchen timer rings"; our code now listens instead of pacing in the doorway.

## 2026-07-17 — SwiftData Reset Stopped Taking The Trapdoor

A UI test crash pointed straight into CoreData's SQL generator while SwiftData was performing a change request. The app code looked harmless: `ModelContext.delete(model:where:)` with "delete everything" predicates during privacy reset, logout cleanup, and token/search history clearing. In practice, that route asks SwiftData to build a batch-style delete under the floorboards, and the simulator can abort before Swift ever gets a polite throwable error.

The fix was intentionally boring: fetch the rows and delete the models one by one inside the existing rollback-safe transaction wrapper. It is not the fastest way to empty a warehouse, but these are local reset flows where correctness matters more than shaving milliseconds. The lesson sticks: SwiftData object deletion is the well-lit hallway; model-wide batch deletion is a shortcut we only take after proving the current OS can handle the schema.

## 2026-07-17 — AuraPlay's Ship Review Found The Fire Doors

The release review found three different kinds of “looks fine until the inspector opens the door” problems. The service boundary had let `AnyView` sneak into a contract file, which is like storing stage props in the wiring closet: convenient for a minute, confusing forever. The video-surface protocol now lives with player presentation, while the service contracts are back to pure playback state and commands.

The local-data ledger also got its missing AuraPlay shelves. Media items were classified, but embeddings, NFT token rows, playlists, and playlist items were not. Those rows are not secrets, but they are wallet-scoped behavior and curation records, so they now clear with the dedicated AuraPlay persistence reset phase. Privacy reset is a product contract, not a spreadsheet chore.

Two UI and network lessons landed with it. The full player now keeps dark media chrome readable even when the host snapshot asks for light mode, and the macOS Up Next snapshot path uses a concrete scroll layout so duplicate queue rows actually show up. Artwork prefetching also stopped trusting `Content-Length` after the meal was already on the plate: it now rejects oversized declared bodies early and streams bytes with a hard cap for providers that omit the header.

## 2026-07-17 — AuraPlay Swept The Old Room And Rekeyed The Locks

Two ship blockers closed today. First, the legacy now-playing surface is fully gone: with `AuraPlayNowPlayingView` deleted, this pass removed the furniture that only it used — `AuraPlayRecentlyPlayedSection` and the four recently-played members on `AuraPlayPlaybackPresenting`, along with `AuraPlayRecentlyPlayedItem` and the matching wrapper/runtime/mock conformances. Playback history still exists; it just lives where the new player already looks, in the queue presentation's history roles. One now-playing surface, one contract, no drift.

Second, the last AuraPlay callers stopped freelancing their gateway knowledge. The app-target library sync and the package indexer both normalized artwork through hand-rolled or legacy sanitisers that either dropped `ipfs://` art or duplicated Pinata rewrites; both now route through `URLResolver`, so decentralized artwork resolves the same way everywhere. The video wireframe's gateway-fallback resolver also stopped carrying its own hard-coded host list and now derives it from `AuraPlayStorageResolutionConfiguration`. The legacy `Auralis/Helpers` URL utilities remain only for non-AuraPlay shell callers (`NFTKit`, `AuralisPrimaryModels`) — retiring those is shell cleanup, not AuraPlay debt.

Validation: full MusicFeature package run (95 tests) green under the beta toolchain, and the app builds with test targets. Gaps and Status docs updated to match.

## 2026-07-16 — Phase 10 Put The Mode Switches Where Hands Expect Them

The full player already had a working Up Next room, but shuffle and repeat were hiding in that room like light switches mounted inside a closet. This pass moved those controls onto the main Now Playing surface too, while keeping them wired to the same command path as the sheet. One state source, two convenient handles.

A small accessibility breadcrumb got cleaned up at the same time: the reusable gesture layer now takes its accessibility identifier from the surface hosting it, so artwork and video no longer wear the same test badge. The audio normalisation copy also got more honest about the target: about -14 LUFS from approximate metadata, not a studio-grade promise with a fancy sticker.

## 2026-07-16 — Phase 10 Player Controls Found Their Wires

The full player had the right dashboard labels, but a few buttons were still politely pointing at empty space. This pass connected the Phase 10 player adapter to the runtime and video bridge for the controls that matter: repeat, shuffle, PiP, subtitles/audio descriptions, playback speed, video aspect, route picking, and the real shared video surface. The important architectural move is still restraint: `MusicFeature` gets the reusable UI and command vocabulary, while the app-owned runtime and video wireframe keep the engine keys.

The scrubber learned a small but user-facing memory trick too: remaining-vs-total time now survives relaunch through `AppStorage`. The player gesture layer now sends double-tap seek, middle-tap video chrome, pinch aspect toggling, and swipe-down dismiss through the same command surface, with Reduce Motion changing the feel instead of changing the feature. That is the difference between a pretty control panel and one that keeps working when the room changes.

## 2026-07-16 — AuraPlay Library Stopped Being A Display Case

Phase 9’s library now behaves like a working record shop instead of a museum shelf. Collection rows and creator rows open real scoped detail routes. Playlist rows open a playlist editor with create, rename, delete, remove, and drag-reorder flows wired through the SwiftData playlist actor, so the UI no longer pretends “add to playlist” is the same thing as “add to queue.” Sync got a counter at the front desk too: the Music tab can show discovery progress, completion, errors, and indexing work without learning the sync coordinator’s private plumbing.

Phase 10 moved furniture into the room as well. The mini-player now opens the new Phase 10 full-player shell through an adapter over the live playback presenter, so audio playback uses the new presentation and command contracts while keeping the existing engine stable. The library start path also stopped throwing the whole library at playback. It now seeds a bounded queue window and lazily tops up as the listener advances, which is the difference between handing someone the next crate and dropping the whole warehouse on the turntable.

The useful gotcha: SwiftUI navigation was not the hard part. The hard part was keeping each doorway honest. Item details still belong to the app router, playlist mutation belongs to the playlist actor, sync progress belongs to the sync coordinator, and the player UI talks through presentation/command contracts. The screen feels more complete because fewer things are freelancing.

The final Phase 10 pass made that doorway more than a drawing. The live runtime now hands the new player a full current-item card: media kind, chain, contract, token ID, share URL, explorer URL, and queue mutations. The context menu buttons are not decorative anymore; share, explorer, copy contract, queue delete, and queue reorder all travel through the adapter into real app behavior. Think of it as replacing the cardboard “control panel” with switches connected to wires.

The video side also got a useful audit point: the production video shell is already using `PlayerContainerView` and passes its `AVPlayerLayer` into the PiP controller, so the layer that PiP needs is not trapped behind SwiftUI chrome. The only thing deliberately left outside this pass is the real-device PiP/AirPlay/video QA run, because simulator builds cannot prove route-picker hardware behavior.

## 2026-07-16 — AuraPlay Got Shelves, A Clipboard, And A Bouncer

Phase 9 stopped being a blueprint and became the Music tab’s front door. `MusicFeatureRootView` now opens onto a real `LibraryRootView`: six segments, grid/list browsing, AuraPlay-owned media rows, collection/creator grouping, playlist rows, the existing mini-player mounted at the root, and accessibility IDs registered in the shared `AuraUI` ledger. The old `AuraPlayEntryView` is still around as a useful migration room, but it is no longer the production lobby.

Under the floorboards, AuraPlay gained the missing shelves: duration and last-played metadata on media rows, typed media query windows, ordered AuraPlay playlist tables, and a playlist service that keeps positions gapless after every shuffle of the stack. The important bug-shaped lesson came from Swift 6: SwiftData models are not party favors you hand across actor boundaries. Query windows now return Sendable snapshots, and playlist tests use snapshot helpers instead of smuggling live model objects out of a model actor. The bouncer at the actor door is doing its job.

Phase 10 also has its package-side player room now: presentation contracts, command protocol, full-player shell, coalesced scrubber, Up Next, audio controls, and video chrome. It is still waiting on the live app adapter cutover and device QA, but the UI no longer needs to invent playback state. It watches one clipboard and sends commands back through one counter.

## 2026-07-16 — Phase 10 Drew The Player Room Before Moving The Furniture

Phase 10 is tempting to treat as a prettier Now Playing sheet. The plan pass says no: the existing audio Now Playing view, the video wireframe, and the Phase 8 orchestrator all own useful pieces, but the shipping player needs one shared state-and-command doorway. Otherwise the scrubber, video controls, audio controls, PiP, and queue can quietly become five little playback surfaces wearing the same coat.

The blueprint keeps the player honest. State comes from the orchestrator, media rendering comes from the existing engines, and SwiftUI observes and commands. Audio controls disappear for video, video controls disappear for audio, drag scrubbing and double-tap seeking share one coalescer, and dismissing the full player never stops the music. A full-screen player should feel powerful, but its best engineering trick is restraint.

## 2026-07-16 — Phase 9 Got A Real Library Blueprint

AuraPlay Phase 9 looked like a UI phase at first glance: tabs, cells, playlists, mini-player, snapshots. The plan pass found the important catch hiding under the counter: the current Music tab is still a migration dashboard, and the package is missing some of the contracts a real Library screen would need to avoid theater props. Sort/filter needs a typed media query service. Playlists need ordered AuraPlay-owned rows, not the older unordered `Playlist.tracks` bag. The mini-player needs an orchestrator-shaped contract instead of a tiny playback-controller peephole.

So the Phase 9 plan now starts with the kitchen equipment before plating the meal. Build the query, playback, playlist, grouping, seed, and accessibility seams first; then the Library UI can be built once and reused across grid, list, collection, creator, playlist, and future search. The lesson is a good one: a product screen is only "just UI" when the data and behavior underneath already speak the product's language.

## 2026-07-16 — Phase 5 Tests Got A Shipping Lane

The Phase 5 discovery suite already had the important coverage; today closed the boring-but-critical question of whether the release machinery actually runs it. CI now drives the `MusicFeature` package through Xcode with `xcodebuild test -scheme MusicFeature -destination "platform=macOS"` before the app unit tests, which keeps the Alchemy, Helius, metadata fetcher, parser/classifier, artwork prefetcher, and full NFT discovery integration coverage off the plain-`swift test` road that still trips over SwiftData macro loading on this machine.

The Xcode package plan reports 67 enabled tests, zero disabled, and the Phase 5 file runs its nine lettered scenarios plus the metadata-failure continuation case. Those tests stay local and deterministic: mock provider clients, mock metadata fetches, mock artwork/indexing hooks, and in-memory SwiftData. In coffee-shop terms, we finally checked not just that the kitchen has a fire alarm, but that the building inspection actually pulls its cord.

## 2026-07-15 — Search Learned To Forget And To Wonder

Spotlight indexing had a classic library-card problem: it knew how to add and update cards, but not how to pull cards when a record left the shelf. AuraPlay now treats indexing as reconciliation. If a requested media ID is missing or no longer searchable, the Spotlight client deletes it from the `com.auraplay.media` domain. When sync marks transferred tokens inactive, it also tells the indexer to remove those IDs immediately, so system search does not keep ghost tracks around.

The vector side also moved from warehouse inventory to front-desk service. `AuraPlayEmbeddingService` can now run wallet-and-chain-scoped semantic queries over persisted vectors, rank them with cosine similarity, and hand the Music screen result rows that open, play, or queue the matching media. The UI keeps literal filtering and semantic search separate: one is the exact shelf label, the other is the helpful clerk who understands "late night synth" even when the title does not say those words.

The engineering lesson is small and useful: indexing systems need a delete story on day one, and embeddings are not a feature until there is a query path humans can touch. Persistence is the pantry; search is the meal.

## 2026-07-15 — Phase 5 Got Its Night Shift Crew

Foreground sync is the person at the counter; background refresh is the night shift that restocks the shelves while nobody is looking. AuraPlay now registers `com.auraplay.nft-sync` as a real `BGAppRefreshTask`, declares the required `fetch` background mode and permitted identifier, and routes the task through the same `NFTSyncCoordinator` factory used by the visible Music surface. No second pipeline, no secret shortcut.

The post-sync workers are real now too. Spotlight indexing turns persisted AuraPlay media rows into Core Spotlight documents in the `com.auraplay.media` domain, with a mockable client so tests verify the document contract without poking the device index. Embedding processing persists Float32 vectors in a SwiftData `AuraPlayMediaEmbedding` table, fingerprints source rows, and skips unchanged media for the same Natural Language model revision. Think of it as giving each track both a library card and a semantic scent trail.

The useful pitfall: package tests are only useful if Xcode runs them. The `MusicFeature` scheme still reports zero tests, so the coverage for these production services lives in the active `AuralisTests` plan where CI can actually see it. That is less aesthetically pure than package-local tests, but it is much more honest.

## 2026-07-15 — Phase 5's Old Road Learned The New Video Flag

The normal app build found a small but real contract mismatch: the legacy AuraPlay library projection still handed `AuraPlayMediaItemUpsertRequest` an audio-era shape after Phase 5 taught media rows about video. That old path is like a side entrance to the same theater; even if the new discovery lobby knows whether a token is audio or video, the side entrance still needs to stamp the ticket correctly.

The fix was intentionally narrow. Existing app NFT projections are still audio-first because they only have one sanitized playback URL, so they now say `hasAudio` when that URL exists and `hasVideo: false`. That keeps the production build honest without pretending the older projection path has done Phase 5-style media classification.

## 2026-07-15 — Phase 5 Learned To Fail Loudly And Cache Quietly

The discovery clients had the pipes, but a review found two places where the contract was more implied than proven. Alchemy now has its own direct tests standing at the provider boundary: two-page pagination, empty wallets, ERC-1155 balance handling, and rate-limit retries all run through a mocked `URLSession`, so no test needs to peek at a real API key or wake a real provider.

Rate limits also stopped wearing a generic library-error coat. `AuraPlayError.network(.rateLimited)` is now the package-level signal for Alchemy and Helius after retry exhaustion. That is the difference between telling the app "something went wrong in the basement" and saying "the provider asked us to slow down." The UI can make a better call when the error speaks plainly.

The metadata cache got a quieter second trip, too. The first tokenURI fetch still resolves through the gateway chain and performs the health probe, but successful resolutions are remembered inside `MetadataFetcher`. When the JSON body is already in `URLCache`, the next fetch can go straight to the cached GET response instead of knocking on the gateway door with another `HEAD`.

## 2026-07-15 — Phase 5 Artwork Cache Gets Its Launch Key

P5-007 had the downloader, but the app still needed the kitchen prep station: a shared `URLCache` big enough to make artwork prefetching matter after the first sync. `AppLaunchConfiguration` now installs a 50 MB memory / 500 MB disk cache as the app boots, so `AsyncImage` and the prefetcher are working from the same pantry instead of hoping the default cache has enough shelf space.

The tests now cover both halves of the contract. App-level tests prove launch cache sizing and shared-cache installation, while package-level `MediaItemArtworkPrefetcherTests` exercise mocked downloads, cache hits, oversized-image skips, and Low Power Mode bypasses without touching the network. The small gotcha: `GatewayFallbackChain` still performs its `HEAD` probe before the prefetcher checks for cached GET data, so the cache-hit test expects no extra download rather than zero URLSession traffic. That distinction matters; otherwise the test would be arguing with the architecture instead of guarding it.

## 2026-07-15 — Phase 5 Got A Real Discovery Conveyor

The tempting question was, "Can we just delete `NFTTokenDTO`?" That would be like removing the serving tray because the kitchen already has plates. The DTO is not the final meal; it is the clean handoff between provider clients, metadata parsing, classification, and persistence. Pulling the app's giant SwiftData `NFT` model into `MusicFeature` would make the package boundary sag under furniture it does not need to carry.

This pass gave Phase 5 the missing conveyor belt pieces instead. `AlchemyNFTClient` now implements the EVM discovery contract beside Helius, `NFTSyncCoordinator` walks wallet scopes through fetch, tokenURI fallback, parser, classifier, SwiftData upsert, inactive-token marking, indexing, and artwork prefetch. AuraPlay also has its own persisted token table, so discovery can remember active/inactive NFT tokens without hijacking the older app-wide NFT store. The existing `AuraPlayLibrarySyncing` path still has its job: projecting already-persisted app NFTs into the music library. Phase 5 now has the separate wallet-to-media ingestion route it was missing.

The test story improved but exposed a tooling wrinkle. The nine Phase 5 scenarios now live as Swift Testing integration coverage under `MusicFeatureTests`, using mock clients and in-memory SwiftData. Xcode builds the project cleanly, but the active `Auralis-Fast` plan still only includes `AuralisTests`; the `MusicFeature` scheme currently reports zero tests. SwiftPM can start with its sandbox disabled, but this machine's command-line toolchain cannot load SwiftData macros, so package tests need to run through a properly wired Xcode test action or CI toolchain.

## 2026-07-15 — Phase 5 Came Back To The Real NFT Road

The first Phase 5 map briefly wandered into DTO country. That looked tidy on paper, but Auralis is already shipping its discovery spine through the persisted `NFT` model and `NFTFetcher` provider boundary. Building a parallel `NFTTokenDTO` road would have given us two highways to the same library, with the app trying to remember which one was real.

This pass pulled Phase 5 back onto the production route. Solana discovery now enters through a Helius DAS provider that returns the same `NFT` inventory shape Alchemy uses. The shared fetcher accepts Solana base58 wallets instead of treating every account as EVM, and the app factory selects Helius for `.solanaMainnet` while keeping Alchemy for EVM chains. Missing tokenURI metadata now gets fetched into the existing metadata-prep step, schema-specific media fields patch the real `NFT` fields, and artwork prefetch runs after persistence without blocking refresh completion.

The useful lesson is architectural, not just musical: when an app already has a working conveyor belt, do not build a decorative second conveyor beside it. Upgrade the belt the app actually uses, then make tests stand at the stations where data changes hands: provider page mapping, chain-aware validation, tokenURI fallback, Sound/Zora/ERC-1155 media normalization, and refresh debounce.

## 2026-07-13 — Unit Tests Stopped Opening The Real Record Crate

The test crash hunt started with a suspiciously beta-shaped crime scene: a small account-test batch reported `signal trap` for almost every test, while one pure planner test slipped through. The console told the better story. Before those tests could do much of anything, the hosted unit-test app launched the full Auralis shell, loaded duplicate Swift package classes into the app and test bundle, and tried to open the live AuraPlay SQLite store. That store then hit a migration error for a required `AuraPlayMediaItem.cachedFileStateRawValue` value. The account tests looked guilty because they were nearby when the kitchen caught fire.

The fix is deliberately boring: `MusicAssembly.makeRuntime()` now asks for an in-memory `AuraPlayModelContainer` when `XCTestConfigurationFilePath` is present. Hosted unit tests still exercise the app shell, but they no longer drag yesterday's simulator music database into today's run. This is the engineering lesson: when a unit test crashes before its own code matters, inspect the host app startup path first. Test tags are useful for known beta runner failures; they are not a substitute for keeping live persistent stores out of unit-test bootstrap.

One environment wrinkle remains from the same session: after clearing DerivedData, Xcode beta temporarily reported every local package product as missing even though the package manifests and project references were intact. That is resolver/index state, not a source-code product mismatch.

## 2026-07-11 — Phase 8 Cut The Second Steering Wheel

The remaining Phase 8 problem was not missing machinery. It was ownership. `PlaybackOrchestrator` had the right traffic rules, but live audio playback and remote commands still had a second route through `AuraPlayPlaybackRuntime`. That is how "single source of truth" turns into "single source of truth, except Tuesdays."

The runtime is now the adapter over the conductor instead of a rival conductor. Production audio starts through `PlaybackOrchestrator.play`, the remote command stream binds through `RemoteCommandCoordinator`, and tiny runtime bridge controllers let the orchestrator drive the existing audio engine and video remote-control surface without forcing the SwiftUI presentation layer to change shape. The good pattern here is old-school but reliable: keep the public contract stable, move the authority underneath it.

The new guard test checks that runtime audio still owns a `PlaybackOrchestrator`, binds remote commands through the coordinator, and does not quietly recreate a direct `remoteCommandPublisher.events` consumer. A bug we prevent with a source-level tripwire is a bug nobody has to re-learn during release week.

## 2026-07-11 — Phase 8 Stopped Asking For Migration Permission

The first Phase 8 pass built the traffic controller, but part of the car was still driving around it. That made sense only if a released compatibility contract existed. It does not. For an unreleased app, keeping two playback authorities is not caution, it is clutter with a steering wheel.

This hardening pass tightened the dedicated `PlaybackOrchestrator` instead of preserving the split as a design goal. Completion now has an explicit orchestrator path that marks the finished item, advances the queue, and avoids accidentally rewriting the completed position with the last playback tick. Cadence writes are injectable so tests can prove periodic persistence without waiting five real seconds, and audio start now calls a queue-advance coordinator hook for next-item preparation. The tests now cover all remote command cases, completion advance, cadence plus pause flush, and next-item preparation.

The useful lesson: an ADR is not a spell. Writing "single owner" in a decision record does not make the code obey it. The right unreleased-product move is to make the desired architecture the target and keep tests as the guard rails while the remaining runtime cutover happens.

## 2026-07-11 — AuraPlay Got A Traffic Controller

Phase 8 found the classic media-app trap: two things can be individually correct and still make a mess together. Audio knew how to play. Video knew how to play. Remote commands knew how to shout instructions. But nobody was standing in the intersection making sure only one engine moved at a time, and nobody was checking whether an old async load was still allowed to touch the dashboard after the user had already picked something newer.

The new playback orchestration layer is that traffic controller. `AuraPlayPlaybackQueue` gives every queued occurrence its own `QueueEntry` UUID, because the same song can appear twice and still be two different seats in the line. `PlaybackOrchestrator` owns the main-actor state machine and a playback-generation token, so a slow load from track A cannot wander back later and overwrite track B. The live audio runtime now has the same generation-token guard around URL resolution, cache readiness, scheduling, and engine start.

Position persistence also stopped being a side hustle. `AuraPlayPlaybackPositionState` and its model actor give audio and video one SwiftData-backed place to write current position, completion, and most-recent restore state. The useful lesson is simple: playback state is not a souvenir each engine keeps in its own drawer. It is the app's flight recorder, and there should be one cockpit writing it.

## 2026-07-11 — Video Playback Learned To Stop Keeping Every Receipt

AuraPlayVideoEngine had a good old-fashioned shipping-review catch: not one dramatic crash, but a cluster of small bookkeeping lies. AVFoundation asked the resource loader for a UTI and we sometimes handed it a MIME type. That is the media equivalent of writing "soup" where the shipping form wants a barcode. The fix now translates server `Content-Type` values through `UTType` and falls back to the media file extension when the server is vague.

The player event stream also needed a memory diet. A 60fps tick stream is great while a UI is listening, but unbounded buffering means a plain play/pause host can quietly stack up hundreds of thousands of events. The controller now keeps only the newest buffered playback events, and the package README spells out the single-consumer `AsyncStream` rule so the integration coordinator and queue controller do not accidentally split events between themselves.

The offline download managers got the mop-and-bucket pass: progress observers unregister when listeners leave, terminal records finish streams, successful URLSession tasks leave the task registry, and unknown zero-progress callbacks no longer get persisted over completed downloads. The broader lesson is the boring one that saves products: every async stream, task map, and delegate callback needs an exit strategy.

## 2026-07-10 — Video Plugged Into The System Desk

The video player had plenty of buttons on the counter, but a few were still wired like a rehearsal board: the app view drove playback directly while the engine's integration coordinator sat nearby with the system plugs for Now Playing, remote commands, persistence, gateway fallback, and background PiP. That is like having the stage lights patched into the practice dimmer instead of the theater console.

`AuraPlayVideoWireframeView` now creates a real `VideoPlaybackIntegrationCoordinator` for the selected wallet-scoped video. The view still owns the SwiftUI dashboard, but it forwards playback events into the coordinator so Lock Screen metadata, remote play/pause/scrub commands, position writes, media-session interruption handling, completion resets, and gateway recovery all run through the shared engine contract. The speed picker now starts from the stored speed, and Audio Descriptions get their own explicit menu instead of being merely listed as detected tracks.

The useful boundary is still honest: this finishes the code wiring, not hardware certification. PiP, AirPlay routes, HDR display behavior, remote commands, and Lock Screen controls still need real-device QA because simulators and unit tests cannot prove the system UI actually behaves in the user's hand.

## 2026-07-10 — PiP Learned The Way Back To The Theater

The first Phase 7 video UI pass had the right player machinery, but PiP restoration still had a small navigation trap: when the system asked the app to restore the interface, the view opened fullscreen without first making sure the Music video route was actually back on screen. That is like turning on the projector before walking the viewer back into the theater.

`AppRouter` now has an explicit `restoreMusicVideoWireframe()` route contract. The PiP delegate closure calls that before presenting fullscreen, and the router avoids stacking duplicate `.video` routes if restoration fires more than once. The same tune-up aligned smart resume so the button appears for every saved position the helper considers resumable, and the HDR badge now checks display EDR headroom instead of treating wide color as proof of HDR hardware.

The lesson: media UI restoration is a shell contract, not just a player callback. The engine can ask for the screen, but the app router has to know how to put the user back in the right room.

## 2026-07-10 — Phase 7 Video Got Real Hands On The Controls

The video engine already had a serious toolbox, but the app surface was still treating some of those tools like display models behind glass. This pass moved the important pieces onto the actual AuraPlay Video screen: the AVPlayerLayer surface now catches double taps for 15-second seeks, pinches for zoom, and uses Liquid Glass chrome for the controls that live on top of the picture.

The library also learned a good media-app survival trick: when metadata art is missing, generate the poster from the video itself instead of showing a generic tile. That is like labeling a movie shelf with frames from the film rather than blank index cards. Playback got stricter too: unsupported formats raise a toast and skip forward, failed loads get video-specific warnings, saved positions only offer resume when they are truly in the middle, and prolonged gateway stalls try another gateway before giving up.

The subtle platform lesson was orientation and PiP. A SwiftUI view can know a video is landscape, but UIKit still has to enforce the app's rotation policy. The new orientation bridge keeps portrait/square media locked upright and lets landscape media rotate. PiP restoration now returns users to the fullscreen player instead of quietly closing the presentation door it was supposed to reopen.

## 2026-07-09 — The Mini Player Got Its Warning Light

The final Audio Engine v1 UI polish was not a new music feature so much as a trust feature. Now Playing already had the detailed dashboard, but the mini player followed users around the app like a tiny status strip. If a track was buffering, downloading, saved offline, pinned, or stuck on a cache error, that little strip needed to say so instead of making users open the big cockpit to check the gauges.

`AuraPlayMiniPlayerView` now shows a compact buffering/offline/cache row under the scrubber whenever active playback or cache state needs attention. The same pass made offline-unavailable and corrupted-cache failures use the top playback warning path, matching unsupported-format and engine-start failures. The useful lesson: an audio app should not hide recoverable trouble in the room the user just left.

The docs now call the Audio Engine v1 UI implemented across Now Playing, mini player, and Settings. The remaining gate is the honest one: real-device QA for routes, interruptions, Lock Screen, background playback, poor networks, audible transitions, offline launch, and battery.

## 2026-07-09 — Settings Finally Reached The Live Mixing Desk

The last AuraPlay settings gap was subtle because the controls looked real: EQ, loudness, AutoMix, and offline preference all wrote to `UserDefaults`. But the already-running audio engine had its own in-memory knobs. That is like changing the recipe card in the kitchen binder while the chef is already cooking from memory.

`SettingsView` now receives the shared `AuraPlayPlaybackRuntime` from `MainTabView`. When a user changes EQ, custom band gains, normalization, or AutoMix from Settings, the same runtime methods used by Now Playing fire immediately. Opening Settings also syncs from the runtime first, so the global panel and player panel no longer drift apart.

The offline toggle still stays conservative: turning it on asks the runtime to pin the current track when possible and updates the durable preference for future cached tracks. Turning it off stops future automatic pinning without silently undoing any explicit pin a user already made.

## 2026-07-09 — AuraPlay Closed The Three Annoying Escape Hatches

The latest audio pass was not about glamorous controls. It was about the three places users could still fall through the floor: errors that only lived as quiet panel copy, an offline preference that did not exist globally, and system route interruptions that paused the engine without telling the SwiftUI state machine. That is like the stage manager cutting the music but forgetting to tell the light board.

`AuraPlayPlaybackRuntime` now raises a real playback warning surface for critical engine-start failures and unsupported formats, and queued unsupported tracks are skipped instead of stranding the listener on a dead item. Settings gained a `Download for offline` preference, backed by `AuraPlayAudioSettings`, so cached tracks can be pinned automatically rather than relying only on the per-track button.

The recovery path got the most important little contract: `EngineRecoveryCoordinator` now publishes a paused recovery event for route loss and interruption start. The runtime consumes that event, updates play/pause state, stops display ticks, and keeps Now Playing honest. Lesson: in media apps, the engine being correct is only half the work; the dashboard has to learn about every forced state change too.

## 2026-07-09 — Phase 6 Gave The Lock Screen Its Own Clock

The Phase 6 UI review found a small but important loose wire: the Lock Screen had a purpose-built 0.5-second elapsed-time ticker in `NowPlayingPublisher`, but the host runtime was not actually starting it. The app was updating Now Playing from the playback display loop instead, which is like asking the speedometer needle to double as the dashboard clock.

`AuraPlayPlaybackRuntime` now starts the Now Playing elapsed ticker when real playback is active, restarts it after seeks so the system clock resumes from the new position, and stops it for pause, stop, error, or clear. The visible SwiftUI was already showing the right Phase 6 controls; this fix makes the system playback UI tell time through the machinery built for it.

## 2026-07-09 — Phase 6 Got The Missing Knobs And Warning Lights

The last Phase 6 pass found the kind of UI gap that sneaks into audio apps: the engine had real muscles, but the user could only reach some of the controls from the Now Playing room. That is like hiding the house thermostat behind the stereo cabinet. EQ, loudness normalization, and AutoMix are preferences, not just per-screen curiosities, so Settings now has a real AuraPlay Audio section.

The fix also turned "custom EQ exists in the engine" into "custom EQ exists for humans." `AuraPlayAudioSettings` is the shared little recipe card for default keys, band labels, gain limits, and stored custom gains. Settings and Now Playing both read the same card. The runtime applies the same card to `AudioEngineController`, so the sliders are not decorative faders; they move the actual 10-band engine preset.

The other missing warning light was playback failure copy. Unsupported formats and offline-missing media now get specific product messages instead of the old shrug of "could not load." That matters because users can act on "this `.ogg` is not supported yet" or "this is not saved on this device"; they cannot do much with a mystery failure.

The remaining truth is hardware. The Phase 6 checklist now names the real-device gate for AirPods, calls, Siri, Lock Screen, background playback, poor networks, audible gaplessness, and battery. Code can wire the dashboard. A physical device still has to take the car onto the road.

## 2026-07-09 — Phase 6 Put Real Wires Behind The Dashboard

The earlier Phase 6 audit found the uncomfortable kind of almost-done: the buttons were visible, the engine package was capable, but some of the wires stopped behind the panel. AutoMix had a slider but no runtime handoff, Lock Screen artwork had a publisher but no artwork payload, cache/loudness lived in the engine but not in the app's durable media row, and the progressive-underrun recovery hook was waiting on the bench like a spare tire no one had mounted.

The fix was to make the host runtime own the handoff. `AuraPlayPlaybackRuntime` now tracks the prepared next NFT and media record, schedules crossfade ramps when AutoMix is enabled, watches the engine's automatic transition counter, and promotes the app's current-track metadata when the engine swaps players. In other words: when the engine changes lanes, the dashboard follows instead of yanking the car back to the old lane and reloading the next song from scratch.

Now Playing got the same honesty pass. Artwork is fetched before publishing system metadata, so the MediaPlayer artwork handler stays synchronous while Lock Screen and Control Center can receive the actual cover. Cache and approximate loudness also learned where to live after the app quits: `AuraPlayMediaItem` gained additive fields, the AuraPlay store now opens through a versioned migration plan, and the model actor has a playback-state update method. The cache manager still keeps its fast JSON index for file eviction, but the product-facing media row now remembers the state users care about.

The remaining truth label is physical QA. Code can now connect the promised paths; only a real device can prove AirPods, interruptions, route changes, Lock Screen controls, bad networks, and battery drain behave like a shipping audio app.

## 2026-07-09 — Phase 6 Learned The Difference Between Engine Ready And Ship Ready

The audio package is now wearing its hard hat correctly: cache, gapless scheduling, recovery, EQ, normalization, Now Playing, remote commands, AirPlay route policy, and the deferred spatial/voice boundaries are all documented as package-side reality. But a package is not a product. It is the engine on a test stand; the app still has to bolt it into the car, connect the dashboard, take it onto actual roads, and make sure the steering wheel works when AirPods, phone calls, Lock Screen controls, and bad networks show up.

`AuraPlay-Gaps.md` now tracks that distinction directly under Phase 6. The remaining gate is host integration and physical-device QA: real queue state, user controls, route selection, cache persistence, app-owned media adapters, loudness persistence, disciplined Now Playing publication, `AVInitialRouteSharingPolicy = LongFormAudio`, and the manual checklist. That keeps the docs honest: Phase 6 infrastructure can be ready without pretending every product edge has been signed off.

The lesson is useful beyond audio: never let a green package test suite impersonate a shipping experience. Automated tests can prove the workshop machinery. Hardware QA proves the thing survives the weather.

## 2026-07-08 — Phase 6 Audio UI Got Its Dashboard

Phase 6 had the engine room: cache, progressive local-file playback, EQ, normalization, AutoMix, recovery events, and system metadata. What it did not fully have was the dashboard. That is a problem because a user cannot steer from inside the boiler room, and a reviewer cannot sign off a feature by reading gauges hidden behind a wall.

The Now Playing surface now exposes the Phase 6 controls that belong in a player: EQ presets, loudness normalization, AutoMix duration, transition quality, cache/buffering state, recovery state, and spoken-word processing status. The runtime is no longer just playing sound; it is translating engine events into human-readable status. If a file is playable while still downloading, the cache panel says so. If the engine recovers from a route change or interruption, the recovery row has a place to tell that story.

The lesson is the usual media-app lesson: advanced audio work should be mostly invisible until the user needs agency or trust. EQ and AutoMix are agency. Buffering, offline state, normalization, and recovery are trust. Put those on the dashboard, keep the graph details in the engine room, and make sure every visible switch has a real wire behind it.

## 2026-07-08 — AuraPlay Got Backing Behind The Buttons

The second AuraPlay UI pass turned the earlier honesty rule into a shipping rule: a control can show up only when there is machinery behind it. Audio now publishes real Now Playing metadata, listens to system remote commands, and gives the active track real save/pin/unpin cache controls. The 15-second skip buttons now match the runtime and remote-command convention, so the UI and engine finally clap on the same beat.

Video grew up from a demo room into a wallet-scoped playback room. Instead of asking users for raw media URLs, it pulls video-capable library items for the active account and chain, resolves them through the shared resolver, and opens them in an AVPlayer-backed surface with PiP, fullscreen, route, speed, subtitle, audio track, chapter, and resume controls. The AuraPlay root also gained search, filters, and sorting so a real library can be scanned instead of admired from a distance.

The important restraint stayed intact: shared sessions, video offline downloads, immersive handoff, multiview, EQ, and visualizer work are still not fake-shipped. They remain documented as future doors that need real hinges first.

## 2026-07-08 — AuraPlay Stopped Showing Fake Doors

The AuraPlay UI requirements report had one rule that mattered more than any shiny control: do not ship buttons that cannot do the thing they advertise. A disabled PiP button, a disabled offline button, or a route-mode picker that never changes routes is like putting a beautifully labeled elevator panel on a painted wall. It looks ambitious for a demo and dishonest in a product.

The Music tab now leans into that honesty. Audio skip controls say and do the same thing: 15-second seeks, matching the package remote-command convention. The Now Playing integration panel keeps real AirPlay routing visible, but turns unwired route/offline behavior into readable status rows instead of fake controls. The video surface no longer exposes a raw resolved URL field or dead PiP/fullscreen/download/subtitle buttons; it loads sample media through a production-shaped player shell with real play/pause, seek, speed, AirPlay, and designed loading/error/buffering copy.

The lesson is simple: a media app earns trust by making unavailable capability quiet, not tantalizing. When the host adapters arrive, the controls can return with real state behind them.

## 2026-07-08 — The UI Audit Zoomed Out

The AuraPlay UI report started as a shopping list for the media workshop, then grew into a map of the whole storefront. That matters because a music/video feature does not live in a display case by itself: users enter through onboarding, switch wallets through chrome, search across local objects, bounce through token detail screens, recover from provider failures, and eventually ask Settings to clean up the local trail.

The now-retired `AuraPlay-UI-Requirements-And-Gaps.md` named that wider contract at the time. The app is not just a pile of placeholders; Home, Search, Gas, NFT tokens, ERC-20 holdings, Settings, Profile, onboarding, shell restore, and global chrome all have real UI. The honest gap is proof: device QA, accessibility inspection, release-vs-debug surface visibility, and ugly-state testing across providers, caches, deep links, and destructive confirmations.

The lesson is a good product-audit rule: do not call a feature report complete until you trace the doors into and out of it. AuraPlay can have the best media controls in the world, but if Search, chrome, account switching, or offline/provider states lie to the user, the experience still leaks.

## 2026-07-08 — AuraPlay Got Its UI Shopping List

The three AuraPlay media packages were starting to look like three well-stocked workshops with no shared shopping list for the storefront. Audio had playback machinery, video had a serious AVFoundation toolbox, and MediaCore had the language for shared sessions, but the app needed one honest ledger of what the user can actually touch.

The now-retired `AuraPlay-UI-Requirements-And-Gaps.md` was that ledger. It separated present controls from placeholders, package-only capabilities from app-wired behavior, and real product requirements from tempting demo scaffolding. The big lesson is that package readiness is not the same as product readiness. A PiP controller is not a PiP experience until the app owns restore behavior. A shared session contract is not SharePlay until real participants, queue identity, and attribution are visible. An offline manager is not offline UX until users can start, cancel, retry, and trust what is cached.

The next useful move is not to wire everything at once. Start by making current audio and video controls truthful, then add host adapters one at a time so the UI never promises more than the app can back up.

## 2026-07-08 — AuraPlay Moved Out Of The Old Audio Engine

The old app-local `AudioEngine` had become a two-story building: downstairs it owned AVFoundation playback, upstairs it kept AuraPlay queue state, mini-player presentation, gateway resolution, and receipt logging. That made migration awkward because replacing the engine risked ripping out the dashboard along with the motor.

The fix was to move the motor to the new `AuraPlayAudioEngine` package and keep a small app-level concierge named `AuraPlayPlaybackRuntime`. The runtime still speaks the contracts MusicFeature already expects: playback controls, mini-player presentation, queue counts, recent items, and receipt hooks. But when sound actually needs to happen, it delegates to `AudioEngineController`, `MediaCacheManager`, and `GaplessScheduler` from the package.

The lesson: a migration seam should preserve the product conversation while swapping the machinery behind the counter. The UI still asks, "what track is playing?" and "what is next?" The answer now comes from a runtime that knows AuraPlay, while the heavy AVAudioEngine work lives in the package built for it.

## 2026-07-08 — SharePlay Got Its Invitation Card

The intro SharePlay session was less about transport mechanics and more about the invitation. A SharePlay activity needs a real identity: a unique reverse-DNS-style activity identifier, a title that names the activity rather than the app, a useful subtitle, a preview image that represents the shared thing, a fallback URL, and the right system category. That invitation card is what makes the system UI feel trustworthy instead of vague.

`AuraPlayMediaCore` now has that neutral invitation model. Activities can describe their SharePlay type, app-specific launch payload, preview image identity, supported group contexts, and supported platforms. FaceTime, Messages, and AirDrop are now first-class contexts in the contract, with AirDrop also represented as a launch surface because nearby SharePlay still starts through the same share machinery.

The practical product lesson is still restraint: MusicFeature should not show SharePlay UI until a GroupActivities adapter can back it with a real activity, metadata, and session state. The core now knows what a good invitation looks like; the app layer still needs the actual doorman.

## 2026-07-08 — SharePlay Got A Shared Backpack

`GroupSessionJournal` adds the missing backpack for SharePlay: not every shared thing is a tiny message. Photos, annotations, voice notes, PDFs, and other user-generated files need attachment semantics instead of being shoved through the messenger like furniture through a mail slot.

`AuraPlayMediaCore` now models that backpack without importing GroupActivities directly. Shared attachments have IDs, kinds, display metadata, byte counts, content types, source participants, lifecycle rules, and add/remove mutations. The policy encodes the important WWDC constraints: 100 MB per attachment, end-to-end encryption expectations, and late-join catch-up without forcing everyone to re-upload the same blob.

The design line is deliberate: use the journal for user-generated or collaboratively added attachments, not for primary media like a movie or NFT track that should come from a server or gateway. In AuraPlay terms, journal attachments are for the stuff people bring into the room together; the room itself still needs proper media URLs, caching, and provider validation.

## 2026-07-08 — SharePlay Learned How To Start And How To Whisper

The next SharePlay session filled in two gaps around the shared-room model. First, the app needs to know where a SharePlay activity can start: the share sheet, an in-app button, or a contextual menu. `AuraPlayMediaCore` now models that launch policy directly, including whether the share sheet should register the group activity prominently, quietly, or not at all.

Second, not every SharePlay message deserves the same delivery promise. Playback state, queue identity, participant presence, and control actions are reliable traffic: they are the signed receipts of the room. Real-time hints are different. If a transient scrub preview or gesture point arrives late, it can be worse than dropping it. The core now has a delivery policy that names reliable and unreliable traffic, using the WWDC 256 KB payload ceiling as the shared limit.

The ownerless-session lesson also turned into a contract. Staged sessions can carry each participant's initial playback contribution, so the future GroupActivities adapter can reconcile what everyone thinks the session is before the app starts playing. No single phone gets to be king of the room; the state has to survive handoff, late join, and system-ended sessions.

## 2026-07-08 — SharePlay Got Its Session Passport

The SharePlay plan moved from sticky-note wisdom into code. `AuraPlayMediaCore` now has the neutral session passport: activity identity, participant presence, lobby and late-join policy, queue/session identity, and attribution for who caused a playback change. That last bit matters because shared playback can otherwise feel haunted: the screen moves, but nobody knows whose hand touched the controls.

`AuraPlayVideoEngine` also learned the first practical rule of coordinated video: if people are watching together and someone backgrounds the app, PiP is not a bonus feature, it is the bridge that keeps them in the room. The integration coordinator now accepts a coordinated-playback configuration plus an injectable PiP controller, and only auto-starts PiP on backgrounding for coordinated sessions. Local playback keeps its old behavior.

The MusicFeature SharePlay button stays skipped for now. There is still no live GroupActivities adapter or truthful participant/session state in the feature layer, so adding a shiny button today would be a fake door. The right next move is to wire the shared session contract to real SharePlay sessions, then let MusicFeature present controls and presence once it can tell the truth.

## 2026-07-08 — SharePlay Is A Shared Room, Not A Bigger Play Button

The SharePlay session reframed AuraPlay’s future group mode in a useful way: do not start by asking "how do we broadcast playback?" Start by imagining everyone standing around the same record player. Anyone can touch the controls, everyone should know who is in the room, and if the music changes because someone else acted, the app needs to make that cause visible instead of leaving the screen to move mysteriously.

For Auralis, the adoption path should keep the boundaries clean. `AuraPlayMediaCore` can own neutral SharePlay vocabulary such as activity identity, participant presence, late-join policy, and shared-control attribution. `AuraPlayAudioEngine` and `AuraPlayVideoEngine` should own the AVFoundation coordination details: `AVDelegatingPlaybackCoordinator` for the current custom audio engine path, and `AVPlayerPlaybackCoordinator` for video where `AVPlayer` is the natural transport. `MusicFeature` should own the human part: SharePlay launch affordances, descriptive activity metadata, participant/lobby surfaces, and contextual notices like "Priya skipped to the next track."

The sharp edge is queue identity. Apple’s coordinator can keep time and rate aligned, but it does not decide that every participant loaded the same NFT-backed item. AuraPlay needs a shared media-session contract before real SharePlay controls ship, or synchronized playback will be standing on mismatched queues.

## 2026-07-07 — Media Core Took Over The Boring Plumbing

The next AuraPlay cleanup moved the stuff that never really belonged to "audio" or "video" in the first place: URL downloading contracts, progressive/resumable download handles, network availability, offline download state, and engine logging. Those are the pipes and gauges in the media building. Whether the room is playing a song or a film, the plumbing has the same job.

`AuraPlayMediaCore` now owns those neutral seams with media-shaped names, while the engine packages keep compatibility aliases where existing code expects audio or video vocabulary. `AuraPlayAudioEngine` still has the concrete cache manager and URLSession downloader. `AuraPlayVideoEngine` still owns its asset loader and offline record details. The shared layer only owns the reusable contract language, which is the right amount of DRY: one dictionary, not one giant engine.

## 2026-07-07 — Video Stopped Inventing A Separate Media Passport

`VideoPlayableMedia` used to be its own little border checkpoint: `videoMediaID`, `videoTitle`, `videoArtist`, `videoArtworkURL`, and `resolvedPlaybackURL`. That worked, but it made video media look like a different species from the shared `AuraPlayableMedia` contract. The video engine now asks for the shared passport instead: an `AuraPlayableMedia` transport/cache identity plus `MediaMetadata`.

`AuraPlayMediaCore` now has `AuraPlayableMediaItem`, a small value that bundles the playable URL, declared format, cache state, content kind, optional loudness, and neutral metadata. `AuraPlayVideoEngine` still keeps the `VideoPlayableMedia` name for its public surface, but that protocol now refines `AuraPlayableMedia` and gets video-style accessors from metadata/source URL. In other words, old video call sites still read like video code, while the real model underneath is shared with audio.

The important engineering lesson: compatibility does not have to mean keeping the old shape as the source of truth. The trick is to move the truth into the shared layer, then leave thin adapters where they make existing code and migration easier to read.

## 2026-07-07 — AuraPlay Shared Contracts Learned Their Common Language

The first media-core pass moved the obvious nouns, but audio and video still had a few cousins wearing different name tags. Remote commands, now-playing snapshots, media session events, generic metadata, and gateway URL resolving now sit in `AuraPlayMediaCore`, where both engines can point at the same dictionary instead of translating at the border.

The migration kept the old engine-facing names as aliases where that buys compatibility. Audio still exposes `RemoteCommandEvent` and `NowPlayingState` through `AuraPlayAudioEngine`; video still exposes names like `VideoRemoteCommand` and `VideoMediaMetadata`. Underneath, though, the shared contracts are now the source of truth. Concrete system publishers, AV session managers, resource loaders, cache managers, and anything that smells like AVFoundation wiring stayed in the engine packages where they belong.

Validation had two separate potholes. The core package test suite passed under the matching Xcode beta toolchain. The audio and video library targets also built cleanly. Full audio package tests still trip over the SwiftUI demo executable because the local plugin server cannot load `SwiftUIMacros.StateMacro`, and the workspace build is currently blocked by DerivedData/module-cache writes failing with “No space left on device.” The code signal we needed still came through: the shared contracts compile in core, audio, and video.

## 2026-07-07 — AuraPlay Media Core Became The Shared Counter

Audio and video had each started building their own little media vocabulary, which is how two kitchens end up with different labels for the same salt. `AuraPlayMediaCore` is now the shared counter between them: playable media identity, content/cache state, cache progress/key contracts, shared playback ticks, and the base `AuraPlayError` live in one neutral Swift package.

The migration is deliberately gentle. `AuraPlayAudioEngine` and `AuraPlayVideoEngine` now depend on the core package, but they keep source-compatible public names through typealiases and re-exports. That lets existing call sites keep importing the engine they already use while the real contract has a single home underneath.

Two useful gotchas surfaced while validating the packages. First, CommandLineTools in this environment can build the library products, but it cannot load SwiftUI or Swift Testing macro plugins, so demo executables and package tests need the full Xcode toolchain. Second, the video package had a couple of macOS build traps hiding in platform guards: external-screen playback and AVRouting participant preferences are not available the same way on macOS. The fix was not a media-core concern, but it was the toll booth we had to clear before the new dependency graph could prove itself.

## 2026-07-01 — AuraPlay Video Got An Empty Room

AuraPlay video now has a reserved local package named `AuraPlayVideoEngine`, sitting beside the other first-party packages. It is intentionally only a scaffold right now: no engine code, no playback models, no queue types, no loaders, no AVFoundation or AVKit wrapper, and no tests.

The demo app is just a labeled placeholder screen. The useful move is organizational, not technical: video now has a place to grow later without borrowing shape from the audio work or quietly moving existing media responsibilities before the contract is designed.

## 2026-07-01 — AuraPlay Audio Got An Empty Workshop

AuraPlay audio now has a reserved local package named `AuraPlayAudioEngine`, sitting beside the other first-party packages. It is intentionally only a scaffold right now: no engine code, no playback models, no queue types, no loaders, no AVFoundation wrapper, and no tests.

The demo app is just a labeled placeholder screen. That sounds underwhelming, but it is the right kind of boring: the workshop exists before the tools arrive, and the shipping app `AudioEngine` stays untouched until the new contract is designed on purpose.

## 2026-06-07 — Wallet Connectors Got Their Own Workshop

Third-party wallet work now has a clean side garage instead of being welded straight onto the main app while the engine is running. `WalletConnectorKit` is a new local Swift package for MetaMask, Rainbow, Coinbase Wallet, Phantom, and whatever specialized connector code comes next. The package starts with provider identities, supported chains, connection-method descriptors, a connector protocol, and a registry that routes connect/disconnect calls by wallet provider.

The demo app target is deliberately a showroom with cardboard wiring: it uses stub connectors so the team can build the UI and state model before real deep links, SDK callbacks, universal links, and browser-extension flows start bringing their own weather. That is the useful architectural lesson here: isolate the workshop first, then let each wallet integration become a replaceable tool on the wall instead of a mystery cable running through the app shell.

## 2026-06-07 — AuraPlay Phase 3 Shipped The URL Front Desk

The Phase 3 closeout turned the storage-resolution story from "the code is probably fine" into a shipping record. The docs now agree on the exact boundary: `URLResolver` is the deterministic front desk for IPFS, Arweave, HTTP/S, and `data:` inputs; `GatewayFallbackChain` is the network-facing layer above it; and the rest of AuraPlay should consume those seams instead of copying old helper tricks into new screens.

The useful lesson is that a phase can be complete without every downstream caller being migrated. That is not a loophole; it is the whole point of a seam. Phase 3 built and validated the door. Phase 5 gets to move real traffic through it, one product path at a time.

## 2026-06-06 — AuraPlay Phase 3 Built The Storage Bouncer

AuraPlay's storage resolver is now its own front desk instead of a handful of side doors in the app target. `URLResolver` lives in `MusicFeature`, classifies IPFS, Arweave, HTTP/S, and `data:` inputs, and turns the good ones into URLs the rest of the music stack can reason about. The old helpers were useful trail markers, but the new path keeps detection, validation, gateway choice, and fallback probing in one module-owned lane.

The interesting engineering wrinkle was `data:` URIs. The resolver is supposed to be pure and synchronous, but inline media is already the whole file wearing a URL costume. So Phase 3 gives it one bounded exception: decode, cap at 50 MB, and write a deterministic temp file. Think of it like checking a very large coat at the door; allowed, but tagged, size-limited, and never mistaken for normal traffic.

## 2026-06-05 — Phase 5 Got Its Shipping Stamp

The Phase 4/5 closeout had one awkward truth left: the board said "complete," but the fast test plan still let one slow provider suite sneak into the lunch line. That is how a tag becomes a sticky note instead of a routing rule. `Auralis-Fast` now skips every currently tagged slow/architecture app suite by name, and `Auralis-Slow` gives those heavier tests their own lane until Xcode's test-plan editor can promote the setup to real tag filters.

The fixture cleanup also finished the migration story. `AppRouterTests` and `SwiftDataViewServicesTests` stopped hand-rolling tiny local NFTs and receipts and now use the shared `NFTFixture` / `StoredReceiptFixture` builders. The old refresh helper file left the target entirely. Lesson learned: a phase is ship-ready when the code, the plan files, and the tracker all agree about what is done and what is honestly future work.

## 2026-06-05 — Phase 3 Finally Got Its Receipt

Phase 3 was functionally done, but the ticket board still looked like a kitchen where every completed prep bowl had a sticky note saying "maybe." The last cleanup removed the little per-file `makeContainer()` wrappers that were mostly hiding the real schema choice. Tests now call `TestModelContainers.inMemory(TestSchemas.receipts)`, `TestModelContainers.primary()`, `MusicFeatureTestModelContainers.libraryIndex()`, or `NFTKitTestModelContainers.refresh()` directly, so the reader can see which pantry a test is using without following a tiny detour.

The useful lesson is that completion is not just code passing. A refactor phase earns its closeout when the validation commands, the ticket checkboxes, and the code all tell the same story. For Phase 3, that story is now clean: package tests live with their packages, SwiftData schemas live behind shared helpers, storage edge cases have coverage, and marker tests are gone.

## 2026-06-04 — Phase 3 Closed The Last Loose Shelf

Phase 3 had one final loose shelf after the package moves: NFTKit still had a `makeNFTRefreshContainer()` helper hand-building the refresh schema. That was better than every test doing it, but it still violated the new rule: test containers should have named homes, not mystery pop-up kitchens.

The helper is now `NFTKitTestModelContainers.refresh()`, matching the pattern already used by the storage packages and MusicFeature. The old ad-hoc function is gone, every NFT refresh/service/persistence test now asks the package test container by name, and the remaining direct schema literals are confined to package-level `*TestModelContainers` helpers. That is the Phase 3 shape we wanted: tests live with their packages, schemas live behind shared helpers, and marker tests have been replaced with behavior or removed.

## 2026-06-04 — The Last Test-Refactor Checkmarks Had To Prove It

The phase-status question found three checkmarks that were more optimistic than the code. One NFT service test still asked only "did a date exist?" which is like checking whether a receipt has paper instead of reading the total. It now unwraps the refresh timestamp with `#require` and asserts it is a real persisted timestamp.

The music tests had a different kind of pantry problem: two files were still hand-building SwiftData schemas. Those model lists now live behind one `MusicFeatureTestModelContainers` helper, so the tests ask for the kitchen they need instead of rebuilding the shelf labels every time. The shared `LockedValue` helper also left `AuralisTestSupport`; the remaining URL mock seam keeps its synchronous handler local to the one app test file that needs it.

Validation had its own lesson. Xcode built the app cleanly and the provider suite passed, but command-line `swift test` still cannot load SwiftData macros from this environment's CommandLineTools. For SwiftData-heavy package tests, Xcode remains the grown-up stove; SwiftPM is still trying to cook with the demo burner.

## 2026-06-04 — Phase 2 And 3 Moved The Tests To Their Real Homes

The unit-test refactor finally stopped treating the app test target like a storage closet for every package's furniture. NFT refresh, metadata, persistence, and receipt tests moved into `NFTKit`; music presentation, receipt logging, and the SwiftData music index moved into `MusicFeature`. That is the architectural equivalent of putting the frying pans back in the kitchen station that actually uses them: local package changes now have local tests watching the contract.

The Phase 2 cleanup was quieter but just as important. The retry-after provider test no longer times the wall clock with a stopwatch, and the last project-owned `@unchecked Sendable` test seams became checked sendable or explicitly synchronous unsafe seams where the production protocol cannot await an actor. Lesson learned: a test suite becomes trustworthy when it owns its clocks, its shared state, and its package boundaries instead of borrowing all three from the room next door.

## 2026-06-04 — Test Safety Found The Real Sendable Door

The unit-test refactor review found one last shortcut hiding in plain sight: the app test target had taught `UserDefaults` to pretend it was safely sendable everywhere. That is like handing one backstage pass to every door in the theater. It made tests compile, but it also blurred the real boundary: an actor that owns `UserDefaults` needs to say so explicitly.

The fix moved that truth into the ENS cache seam with `ENSCacheUserDefaults`, a tiny boxed wrapper used only where the actor needs to carry a suite-scoped defaults store. The image-loader and provider tests got a similar cleanup: synchronous URL mocks still need synchronous recorders, so their old `NSLock + @unchecked Sendable` helpers became checked `Mutex` helpers instead of actors they cannot await.

The coverage lesson was about ownership. NFTKit, MusicFeature, and CodeScanner gained package-local behavior tests so package contracts do not depend solely on app-target integration tests. SwiftPM command-line validation still stumbles on SwiftData macro loading in this environment, so Xcode remains the source of truth for SwiftData-heavy targets.

## 2026-06-03 — Phase 2 Replaced Guesswork With Doorbells

The second unit-test refactor pass was about making async tests stop reading tea leaves. `ShellStoreTests` used to wait for background refresh work by yielding to the scheduler three times, which is basically knocking on a door and hoping someone answers by the third knock. The refresh coordinator test double now rings a proper doorbell: tests wait for an observed refresh count, and no-refresh tests assert immediately.

Time got the same treatment. ERC-20 and AuraPlay fixture dates now use the shared reference date instead of "whatever time the runner happens to be in." The token row model also accepts an explicit `now`, so stale metadata tests can pin the clock instead of racing the wall clock.

The lesson: a deterministic test should wait on the thing it actually cares about. Scheduler hops and wall-clock freshness are fine for production systems, but tests need handles, not vibes.

## 2026-06-03 — Phase 1 Took the Shared Toys Off the Table

Phase 1 of the unit-test refactor started with the test-suite equivalent of labeling the spice rack: shared Swift Testing tags now live in `AuralisTestSupport`, so app and package tests speak the same filtering language. The old app-only tag extension was like a menu only one kitchen station could read.

The bigger bug story was `NFTImageCache.shared`. Image loader tests were clearing one global cache while Swift Testing was free to run neighbors in parallel, which is how a test suite turns into a group project with one eraser. `NFTImageLoader` now accepts an `NFTImageCaching` dependency, and the tests use fresh caches, so cached-image behavior is still tested without borrowing state from the whole process.

The lesson: parallel tests are honest only when their dependencies are private or intentionally coordinated. If a test needs a cache or `UserDefaults` suite, give it its own lunchbox and clean it up afterward.

## 2026-06-03 — The Test Tickets Got Their Prep List

The unit-test refactor ticket list already knew where the cracks were, but it still asked the next engineer to do too much cooking by instinct. `Auralis/docs/plans/Unit-Test-Refactor-Implementation-Runbook.md` now turns the backlog into a prep list: dependency order, exact search patterns, helper shapes, package boundaries, tag rules, and validation gates.

The useful lesson is that a good implementation plan does not just say "fix flaky tests." It names the shared timer, the dirty cutting board, and the shelf each cleaned tool belongs on. Once the work is that explicit, review can focus on whether the code meets the contract instead of debating what the contract was supposed to mean.

## 2026-06-02 — The Test Suite Learned To Name The Broken Plate

Phase 3 and Phase 4 of the unit-test refactor were not about adding a mountain of new assertions. They were about making failures point to the right shelf. Parameterized Swift Testing cases now give table-driven checks their own case names in the navigator, so a policy regression says which identifier broke instead of handing you a mystery red light from the whole pantry.

The cleanup pass also trimmed the paperwork around the suite. Generic account-store test identifiers now read like contracts, the old smoke-test duplication is gone, tags give CI a way to separate slow architecture checks from fast feedback, and initializer-assignment tests have been replaced by round-trip behavior where that actually buys confidence. The one intentional leftover is `@MainActor`: some suites still belong there because SwiftData, UIKit, and SwiftUI are main-actor customers. Lesson learned: maintainable tests are not just fewer tests. They are tests that fail with enough context that the next engineer can fix dinner without reopening every cabinet.

## 2026-06-01 — The Test Suite Got A Real Clock

Phase 1 and Phase 2 of the unit-test refactor moved from plan language into shippable artifacts. The big win is that tests now behave less like someone checking the oven by glancing at the sun: freshness, profile fallback dates, token metadata staleness, ENS cache age, and shell refresh timing all have deterministic clocks where the assertions need them.

The coverage pass was more like putting labels on the pantry shelves. The package targets that used to be indirect passengers now have their own smoke or domain contracts, undercovered presentation tests gained empty and partial-data cases, and the image-loader test stopped peeking through a private `Mirror` keyhole. It now proves the useful behavior instead: once an image is cached, asking again does not hit the network. Lesson learned: a test that watches behavior can survive a refactor; a test that spies on private storage usually becomes tomorrow's cleanup ticket.

## 2026-05-31 — The Test Backlog Learned To Say "Start Here"

The unit-test refactor tickets were a good map, but maps are not work orders. `Auralis/docs/plans/Auralis-Unit-Test-Refactor-Implementation-Brief.md` now acts like the kitchen ticket clipped above the pass: Phase 1 only, clear boundaries, explicit acceptance criteria, and the validation steps needed before anyone claims the test suite is steadier.

The important judgment call was to keep the first implementation slice narrow. The tempting version says "fix all 22 tickets" and then turns into a wandering expedition through every test target. The better version starts with the shaky foundations: sleep polling, global URLProtocol handlers, duplicated support code, real Keychain access, and the privacy reset mega-test. Once those are handled, the remaining cleanup can happen without the floor moving under each assertion.

## 2026-05-31 — The Unit Tests Got A Flight Plan

The unit-test refactor backlog now has a proper map at `Auralis/docs/plans/Auralis-Unit-Test-Refactor-Tickets.md`. The audits all pointed at the same lesson: the suite is not weak because it lacks tests; it is wobbly because a few shared foundations behave like everyone in the kitchen grabbing the same timer, sink, and spice jar at once. `Task.sleep`, static `URLProtocol` handlers, real Keychain access, and `UserDefaults.standard` are the places where parallel Swift Testing can turn a good assertion into a coin toss.

The plan deliberately starts with the plumbing: deterministic async signals, per-session network mocks, and a shared `AuralisTestSupport` package. Once those are in place, the rest of the work becomes much less dramatic: split mega-tests, inject clocks, tighten assertions, tag suites, and give untested packages their own small contracts. Lesson learned: a test suite earns trust less by having more checks and more by making each check independent enough to tell the truth.

## 2026-05-28 — Phase 3 Made Forms Stop Talking Over The User

This Phase 3 accessibility pass was mostly about timing and manners. The search field had been trying to be both an editable field and a status announcer, which is like a cashier reading the menu while you are typing your card PIN. The field now lets SwiftUI expose the actual query text, while the detection card owns the classification context and the existing debounced announcer handles meaningful changes.

The second lesson was that long identifiers need a speaking format, not a bigger megaphone. `AuraAccessibleSpeech` groups hex strings into short chunks so wallet addresses and correlation IDs are still public and useful without becoming one exhausting spoken rope. Loading states also learned to announce starts and finishes, playlist validation can move VoiceOver focus to the inline error, and selected playlist covers now remember whether they came from camera, photo library, or generation.

## 2026-05-28 — Phase 2 Got Its Shared Contracts

This Phase 2 pass was the design-system equivalent of labeling the circuit breaker panel. The card summary helper no longer whispers an empty value into every VoiceOver node, and it can now say what kind of thing a summarized card really is. Receipt previews, receipt timeline rows, and openable token rows get button traits from the shared helper instead of each call site inventing its own little workaround.

The image story also grew a proper contract. `MediaAccessibility` gives feature code two clear doors: decorative images step out of the accessibility tree, while meaningful artwork provides the label people need. NFT gallery images, AuraPlay artwork, and small decorative playback thumbnails now use that same door instead of hand-rolled labels and hides scattered through the app. Lesson learned: accessibility APIs are strongest when the easy path is also the correct path.

## 2026-05-28 — The Audit Started Reading The Receipts

This accessibility fix was less about adding labels and more about making the robot inspector prove the same journey a person would take. The mini-player now speaks the track, artist, artwork context, and playback state from one reachable button instead of hiding useful context behind child artwork that VoiceOver may never land on.

The receipt detail test also stopped looking for a brittle navigation-bar landmark and now opens the seeded receipt from Home recent activity, the way the fixture actually exposes it. Once the test reached the screen, it found the real furniture problems: receipt facts needed a vertical Dynamic Type layout, machine trigger keys like `ui_test.seed` needed human presentation copy, and the gas header needed to stop squeezing a long chain title beside a status pill. Lesson learned: an audit failure is most useful when the route is honest, the copy is human, and the layout can breathe before anyone debates color.

## 2026-05-27 — The Accessibility Audit Became A Map

The project-wide accessibility audit now has a durable home at `Auralis/docs/plans/Accessibility-Project-Wide-Audit.md`. The interesting part is that the app is no longer starting from zero: it already has native controls, named icon buttons, large-text previews, Reduce Motion-aware pieces, and iOS 17 accessibility audit UI tests. The new report is less a panic list and more a map of the last rough terrain.

The big lesson is that accessibility maturity moves from obvious blockers into judgment calls. Is artwork meaningful or decorative? Does a text field value help editing, or does it smuggle in extra status copy? Are preview names proving a setting, or just reminding a human to verify it on real hardware? Those are senior-engineer questions, not checkbox questions, and the audit now names them plainly.

## 2026-05-27 — Phase 5 Put The Audit On Rails

Phase 5 was the testing and process pass: less stagecraft, more making sure the inspector can keep walking the same route tomorrow. The UI-test authenticated fixture now brings its own tiny suitcase: a wallet, a recent search, a receipt, and an NFT. That lets the accessibility audit open populated search history, receipt detail, NFT detail, and external-link confirmation without depending on whatever the simulator happened to remember from yesterday.

The preview bench grew too. Gateway, Home, Search, Gas, Music, AuraUI components, and Now Playing now have named accessibility preview slots while keeping the old large-text and dark-mode checks. The important SDK lesson is that SwiftUI lets us read Increase Contrast, Reduce Motion, and Reduce Transparency, but not force them through `.environment`; those remain real-device settings, not fakeable preview switches. The checklist now carries a grep step for bare accessibility copy, because user-facing VoiceOver strings deserve the same localization discipline as visible text.

## 2026-05-27 — Phase 4 Taught The Quiet Pictures To Step Aside

Phase 4 was the visual-accessibility cleanup: not a repaint, more like making sure the stage props stop introducing themselves during the performance. The empty-state icons in gallery, Home image preview, Now Playing, and Recently Played are decorative, so VoiceOver now walks past them and lands on the actual message. Those messages also get heading semantics, which gives screen-reader users a useful landmark instead of a symbol-name speed bump.

The Dynamic Type work was the other half. Gallery thumbnails, AuraPlay detail artwork, and Recently Played cards now scale from `.body` with caps instead of pretending one pixel size fits every reader. Recently Played already had the right escape hatch: when text gets large, it stops being a sideways carousel and becomes a vertical stack. Lesson learned: visual accessibility is often restraint. Keep the approved palette, scale the furniture, and let decorative art be decorative.

## 2026-05-27 — Phase 3 Had To Prove Its Checkmarks

Phase 3 looked finished on paper, but the proof was too thin around the places users actually get interrupted: validation errors, sheets, and destructive confirmations. The UI test harness now has two deliberate launch doors: one clean gateway and one in-memory authenticated account. That lets the accessibility audit walk into gateway validation, the simulator scanner fallback, account removal confirmation, and the settings reset confirmation without borrowing whatever state happened to live in the simulator.

The gateway validation path also stopped pretending a string was a focus target. The address field already participates in SwiftUI accessibility focus, so validation failure now sets that focus and posts a layout-change notification instead of sending a screen-change event with only the words "Ethereum address" attached. Lesson learned: a checked box is not evidence. A checked box plus the artifact you can grep, build, and operate is evidence.

## 2026-05-26 — Phase 3 Made Forms Speak Up

Phase 3 was the accessibility pass for the spots where users make choices, fix mistakes, and move through small bits of navigation. The gateway stopped doing scale transitions when Reduce Motion is on, destructive account removal now tells VoiceOver that confirmation comes next, and the simulator QR scanner finally has a real "Use simulated code" button instead of asking everyone to understand a tap-anywhere gesture.

The useful center of gravity was announcements. Search history deletion and clear-all actions now confirm themselves, playlist title validation points focus back to the title field and says what failed, and `AuraAccessibilityAnnouncer` grew `screenChanged` and `layoutChanged` APIs so future screens have a proper front desk instead of one announcement-only megaphone.

The visual accommodations stayed intentionally narrow. Local one-off materials now fall back to the existing Aura surface color when Reduce Transparency is enabled, and guest-pass shimmer only appears when motion and transparency settings both allow it. Lesson learned: form accessibility is not just labels. It is the whole conversation: what changed, what needs attention, and which control can fix it.

## 2026-05-26 — Phase 2 Put The Guardrails In The Furniture

Phase 2 was a design-system pass, which means the interesting part was not one flashy screen. It was making the shared pieces behave well before feature code gets a chance to forget. `AuraActionButton` now scales its padding with Dynamic Type while keeping the 44pt tap floor, `AuraPill` has explicit lanes for visible labels, meaningful icon-only status, and decorative icons, and `AuraTrustLabel` stops chopping off the very warning text it exists to communicate.

The card semantics got a shared handle too. `auraAccessibleSummary(label:value:hint:)` turns dense visual cards into one readable VoiceOver item where that is the right interaction model, and the first migrations cover token holdings, receipt timeline rows, receipt previews, and the energy card. Error and success text now use icon-plus-text status instead of relying on color alone, and the unused `PrimaryTextButton` left the room before it became another primitive to harden forever.

Lesson learned: accessibility defaults are like kitchen prep. If the shared ingredients are washed, labeled, and portioned correctly, every later dish has fewer ways to go wrong.

## 2026-05-26 — Phase 1 Learned To Check Its Own Checkmarks

The Phase 1 accessibility board looked closed, but an independent pass found two little loose screws: receipt rows offered a "Copy correlation ID" action even when there was nothing to copy, and the icon-only control guardrail was promised in the ticket without an actual lint rule at the repo root.

The fix was small but useful. Receipt rows now only expose the custom accessibility action when the row has a real correlation ID, so VoiceOver users do not get a dead menu item. The repo also gained a SwiftLint warning rule for icon-only `SystemImage` control labels, which turns future review from "please remember" into a visible tripwire. With those artifacts in place, Phase 1 has been removed from the active accessibility ticket list so the backlog starts at the next real work. Lesson learned: a completed checklist should have artifacts you can point at, then get out of the way.

## 2026-05-25 — The Front Door Got Its Lighting Back

The accessibility pass tried to help the gateway survive rough settings, but it dressed the welcome screen in a raincoat indoors: black text plaques appeared over the scenic image, the primary button lost its purple glow, and the normal-size layout started climbing into the Dynamic Island. Useful accessibility work had accidentally become a redesign.

The fix was not to throw the whole pass away. The gateway now keeps the helpful parts, like larger tap targets, announcements, and scroll/adaptive layout when text sizes actually need it, while normal text sizes return to the intended image-backed composition. Lesson learned: accessibility fixes should make the existing room usable before they start moving walls.

## 2026-05-24 — The Accessibility Gate Needed A Real Door

The accessibility audit suite briefly became too strict in the wrong place: it failed tab audits when the app was still at onboarding, before those audits could reach any tab. That is like failing a fire-drill route because the building key was not issued yet. The tests now skip unreachable tabs in that launch state again, while the gateway audit still runs as the onboarding contract.

The gateway audit then found real UI work. The Paste control had a too-small hit region, the hero button's light-mode gradient did not guarantee text contrast, and several gateway labels were trying to sit directly on scenic artwork. Those labels now get stable opaque text surfaces, and the guest divider no longer squeezes large text between decorative lines.

The lesson: test harness strictness has to point at product behavior, not setup accidents. Once the harness stopped blocking itself, the actual accessibility bugs were small and concrete.

## 2026-05-24 — The Audit Tests Stopped Taking Quiet Detours

A small review found three places where the accessibility finish line needed sharper wording. The UI audit tests now fail when an expected tab is missing instead of quietly skipping the flow, because a release gate should not be able to walk around its own checklist. The chrome search and account controls also moved their accessibility copy onto the localization path, so VoiceOver strings do not become a separate English-only side channel.

The preview story got more honest rather than more theatrical. SwiftUI lets us preview Dark Mode, but Apple documents `colorSchemeContrast` as a read-only value that follows the user's setting, so we cannot force Increase Contrast with a preview modifier. The ticket now says that plainly and leaves Increase Contrast where it belongs: the physical-device release checklist.

## 2026-05-24 — The Last Accessibility Tickets Learned The Difference Between Code And Sign-Off

The final backlog pass was a good reminder that "ready to ship" has two halves. The code half got tighter: fixed avatar and artwork sizes now scale with Dynamic Type caps, the empty image-preview icon can use the Large Content Viewer path, visible-text buttons stopped overriding their own labels, and the automated accessibility audit suite now names the actual critical flows instead of hiding behind one generic launch test.

The preview bench grew up too. `MainTabView` can now preview specific tabs at the largest accessibility text size, and AuraUI has a small component matrix for `AuraSectionHeader`, `AuraActionButton`, `AuraSurfaceCard`, and `AuraEmptyState`. That is the difference between hoping shared components wrap nicely and giving reviewers a standing place to look.

The important caution: some checkboxes are still real-world gates, not code checkboxes. `colorSchemeContrast` and Reduce Transparency are read-only user settings in SwiftUI previews, so the honest path is a physical-device checklist, not a fake preview override. Shipping accessibility needs both the compiler's receipts and a human holding the device.

## 2026-05-24 — The Accessibility Backlog Met The Shipping Gate

The last accessibility pass was less about dramatic UI surgery and more about closing the tiny doors people actually trip over. The legacy playlist row still had a swipe-only delete path, so it now exposes a custom "Delete playlist" action for VoiceOver and Switch Control. The QR scanner got names and hints on its UIKit buttons, moves focus to a sensible control when it opens, and announces scanner failures instead of leaving the error trapped in app logic.

Motion and visual hierarchy got their final tightening too. The home image-preview zoom transition now steps aside when Reduce Motion is enabled, the remaining `withAnimation` call sites were checked for motion gating, and `AuraSectionHeader` graduated from a subtle subheadline to a real headline while keeping the VoiceOver heading trait. Music artwork also learned the difference between decorative album art beside a title and primary artwork that needs to identify itself.

The important release lesson: a checklist is only honest if the device-only boxes stay device-only. Code can make the scanner accessible, previews can catch layout drift, and UI tests can call `performAccessibilityAudit`; but VoiceOver, Voice Control, Switch Control, camera permission recovery, and the Nutrition Label still need a real hand on a real device before anyone calls the release gate closed.

## 2026-05-23 — Phase 3 Put The Labels Where People Actually Look

Phase 3/4 accessibility work moved from the emergency exits into the everyday surfaces. The chrome account button now gives VoiceOver the whole orientation sentence: account plus selected chains, and it lets those labels wrap when the user asks for larger text. The home profile card also stops trying to keep avatar, account copy, and account-management controls in one tight row at accessibility sizes; it stacks like a sensible counter when the room gets crowded.

Guest passes got a similar cleanup. The old card was visually rich but semantically noisy: role icons, metadata icons, barcode decoration, tight tracking, and a low-contrast address label were all competing for attention. Now the card reads as one guest-pass choice, decorative flourishes stay quiet, and the typography relaxes when Dynamic Type gets large.

The small but important lesson: accessibility tickets work best when they stay ticket-sized. Chrome orientation, guest-card semantics, profile layout, artwork noise, and carousel fallbacks are separate jobs. Treating them separately keeps the work shippable and keeps design-review questions from blocking plain fixes.

## 2026-05-23 — The Robot Inspector Got Its Own Clipboard

The accessibility ship gate had a real-device checklist, but the automated side was still living as a sentence in the backlog: add `performAccessibilityAudit` UI tests. That is too easy to lose during release pressure, so `P0-UI-Test-QA-Suite.md` now gives the UI test gate its own home next to the physical-device suite.

The split is intentional. Simulator UI tests are good at catching missing identifiers, broken screen launches, unlabeled controls, and iOS 17+ accessibility audit failures. They are not good at proving VoiceOver, Voice Control, Switch Control, QR scanning, camera permission recovery, and actual hand-feel on hardware. The release contract now says both jobs out loud instead of pretending one clipboard can inspect the whole building.

Lesson learned: accessibility QA needs two inspectors. One is tireless and automated; the other holds the device and catches the parts automation cannot feel.

## 2026-05-23 — Phase 2 Made Accessibility The Default Setting

Phase 2 moved the work from emergency repairs into the shared furniture of the app. Section headers now identify themselves as headings, action buttons enforce a real 44pt hit area, status pills stop creating silent VoiceOver stops, and the core Aura color tokens lean on semantic system colors instead of fixed paint swatches that ignore contrast settings.

The feature fixes followed the same rule: make the primary action semantic, then give secondary actions an accessible path. The mini-player opens through a real Button instead of a tap gesture wearing a label. Recently Played keeps its context menu, but Play, Start Over, and Remove are now custom accessibility actions, with haptics routed through `AuraHaptics` so Reduce Motion remains part of the contract. Gas rows stack at accessibility sizes and read as label/value pairs instead of scattered text. Account and search rows now announce state, target, and destructive actions clearly.

Lesson learned: design-system accessibility is not glamorous, but it is compound interest. One central heading trait or semantic color token pays rent on every screen that uses it.

## 2026-05-23 — Phase 1 Accessibility Stopped Blocking The Front Door

Phase 1 was the part of the accessibility backlog that users would feel immediately: can I get through the gateway at huge text sizes, can I operate the NFT feed without nested controls confusing assistive tech, can I tell which generated image I am picking, and does the app speak up when something changes?

The gateway got the biggest furniture move. Its address entry flow now scrolls, stacks the QR scanner and text field at accessibility sizes, and lets guest passes become a vertical list instead of a sideways hallway. That matters because Dynamic Type bugs are not cosmetic; if the submit button falls off the screen, the app has effectively locked the door.

The rest of the work turned quiet visual cues into usable semantics. Toolbar icons now have names Voice Control can say. Gallery images describe their option number and selection state. Home backgrounds stay decorative and step aside for opaque semantic color when contrast or transparency settings ask for it. Copy, reset, validation, and image-generation events now announce themselves through a shared AuraUI announcer, so VoiceOver users are not left reading smoke signals from changing pixels.

Lesson learned: critical accessibility is usually not one heroic fix. It is a chain of small promises kept everywhere the user touches the app.

## 2026-05-23 — Glass Learned When To Become A Wall

`ACCS-006` and `ACCS-008` kicked off the Phase 1 accessibility work from the design-system end, which is exactly where this kind of fix belongs. Empty states had been wrapping their copy and action buttons into one VoiceOver element, like handing someone a menu where the "retry" button was laminated under the paragraph. The fix keeps the icon/title/message as one readable thought, but lets the primary and secondary buttons stand on their own feet for VoiceOver, Switch Control, and Voice Control.

The surface work had a different flavor. Auralis loves glass, translucency, soft strokes, and image-backed ambience, but users who enable Reduce Transparency or Increase Contrast are asking the app to stop being atmospheric and start being legible. `AuraSurfaceCard` now routes through one shared surface modifier that swaps glass and opacity for an opaque semantic background plus separator border when those settings are active. Guest passes and the Now Playing sheet use that same source of truth, so the fallback behaves like a building code instead of a collection of sticky notes.

Lesson learned: design systems are not just colors and corner radii. They are where accessibility promises become defaults, which means every screen gets better without each feature author remembering the whole checklist.

## 2026-05-23 — The Accessibility Backlog Got A Finish Line

The accessibility audit already had plenty of sharp tickets, but its scoreboard was lying: the header promised 39 tickets while the file actually held 36, and the High-priority count was inflated too. That kind of mismatch is small until someone tries to close the epic and discovers the checklist has phantom chairs at the table.

The plan now tells the truth: 36 tickets, split into 9 Critical, 11 High, 10 Medium, and 6 Low/Polish items. More importantly, it has a completion gate. Accessibility is not done when code compiles or when labels look nicer in review; it is done when the app builds, automated checks cover the flows they can cover, and real-device passes prove VoiceOver, Voice Control, Switch Control, Dynamic Type, contrast, motion, transparency, keyboard navigation, and QR scanning all survive contact with the actual app.

The useful lesson: an accessibility backlog needs two maps. One map says what hurts users. The other says what kind of work each ticket is: implementation, investigation, design review, testing, or process. Without that second map, teams treat a device audit and a one-line label fix like the same species of task, and planning gets mushy fast.

## 2026-05-23 — External Links Stopped Letting Homepages Sneak In

`TEST-010` tightened the outbound-link bouncer. The host allowlist was already picky, but the default action policy still let approved hosts point at their front doors: explorer roots, OpenSea's homepage, and Arweave's root. That is too broad for generated wallet-context actions, where the app should know exactly whether it is sending someone to a token, address, transaction, collection, IPFS object, or Arweave transaction route.

The policy now rejects those root-level action URLs and keeps the paths Auralis actually generates. The confirmation sheet also puts the verified host in the loudest seat at the table, because the hostname is the part a user can realistically verify before leaving the app. The tests pin both sides of the deal: roots are blocked, while explorer `/token/`, `/address/`, `/tx/`, OpenSea asset/collection, IPFS gateway, and Arweave transaction links still pass.

## 2026-05-22 — The Storage Policy Got A Complete Seating Chart

`TEST-002` closed the audit gap where the local data policy knew about a few famous guests but not the whole persistent dinner service. The policy table now registers every active SwiftData model from the primary store and the AuraPlay store, plus the nested NFT models that SwiftData persists behind relationships. Each one carries a classification, storage type, reset phase, and a short reason for why it belongs there.

The useful catch was `Tag`. It was in the primary schema, but privacy reset was not clearing it. Tags are not secrets, but they are user-authored curation metadata, which can say a lot about a wallet owner's taste and intent. They now leave during the transactional reset phase alongside NFT inventory, music indexes, playlists, receipts, and token holdings.

The new tests are the clipboard at the storage-host stand: if a schema model is added without a policy entry, the test fails; if a policy entry is not marked as required, the test fails; if a persisted SwiftData model lacks a reset phase, the test fails. Audit tables work best when they stop being paperwork and start being executable.

## 2026-05-22 — Explorer URLs Stopped Wearing Blindfolds

`TEST-006` was a tiny hardening job with a useful lesson: a literal URL is still input, even when the programmer typed it. `ExplorerCatalog` used to force-unwrap every explorer root, which meant a typo would crash with Swift's generic "found nil" shrug instead of telling us which catalog entry broke.

The catalog now uses a small validated constructor that only accepts HTTPS root URLs with a host and no path, query, or fragment. If a future explorer literal is malformed, the trap points at the bad value like a helpful kitchen ticket instead of dumping the whole tray on the floor. The tests now walk every supported explorer case and verify the catalog root plus the address, transaction, token, and NFT route patterns.

`TEST-007` turned into a verification pass rather than a code rewrite: the receipt reset/integrity files no longer contain force unwraps, and the receipt tests already cover the first receipt, chained receipt, rollback after failed head writes, tamper detection, and intentional reset. Good audit work sometimes closes a ticket by proving the scary thing is gone and keeping the tripwires lit.

## 2026-05-22 — The Feature Packages Got Door Sensors

`TEST-001` turned the architecture boundary tests from a few sharp spot-checks into a package-source patrol. The old tests knew some important doors in `NFTKit`, but feature packages were still mostly protected by good intentions and code review. That is fine until migration work starts moving furniture at speed.

The new guardrail scans `MusicFeature`, `NFTLibraryFeature`, `NFTKit`, and `AuralisPrimaryModels` with rules that match the room each source folder is supposed to be. Presentation folders can import SwiftUI because they are the dining room, not the pantry. Domain and primary-model folders do not get SwiftUI, SwiftData, provider packages, or feature implementation imports. Persistence folders may use SwiftData, but they do not get to reach back into provider adapters or UI.

The sneaky part was Observation. Adding the test honestly meant cleaning up the package code first: AuraPlay playback views stopped using `@ObservedObject`, `AuraPlayPlaybackPresenting` stopped inheriting `ObservableObject`, and `NFTImageLoader` moved to `@Observable` with `@State` ownership in SwiftUI. Lesson learned: a boundary test is a promise, not a poster. If it would fail the current code, either the rule is wrong or the code has to grow up before the rule ships.

## 2026-05-22 — The Signing Door Got A Lock Before It Got A Handle

`WEB3-002` could not honestly be finished end-to-end because Auralis still has no signer, no transaction draft model, and no signing prototype. Building a full preview flow without a transaction would be stage scenery: it might look like architecture, but nothing real would be holding it up.

So the useful move was to install the lock before anyone adds the handle. `PolicyCore` now has a deny-by-default signing chain allowlist, typed execution evidence, a transaction preview protocol boundary, and a readiness evaluator that refuses `draftTransaction` unless the future caller brings signing access, the exact capability grant, requester provenance, user confirmation, an approved receipt, a preview/simulation result, and an allowed target chain.

Lesson learned: future security work can be real even when the feature is not. The trick is to build the contract that future code must satisfy, not a pretend implementation of a flow that does not exist yet.

## 2026-05-22 — Observe Mode Kept Its Hands In Its Pockets

`WEB3-001` looked tempting at first: add `Assist`, add `Operate`, wire a few gates, call it architecture. The catch is that a mode enum is not a security model. In the current code, adding a non-Observe mode before capability grants, confirmation sheets, provenance checks, and approved receipts exist would be like giving the restaurant a "kitchen open" sign before installing the stove controls.

So the shippable move is deliberately smaller and sharper. `AppMode` stays Observe-only, the policy tests now walk every high-risk action (`signMessage`, `approveSpending`, `draftTransaction`, and `runPlugin`) and prove Observe blocks them, and the new ADR says future modes are a product/security release gate rather than a casual enum expansion. `runPlugin` stays on the danger list because tool execution should not become the side door around signing policy.

Lesson learned: future safety vocabulary is useful, but future capability is dangerous until the whole approval pipeline exists. A good gate blocks today and explains exactly what must be built before tomorrow.

The follow-up guardrail made that explanation harder to ignore. ADR-004 now carries a little checklist for each future dangerous door: message signing needs exact preview and signing access, approvals need token/spender/amount preview, transaction drafts need chain and simulation proof, and plugins need identity plus provenance. The tests mirror that checklist with a future contract table tied to `PolicyControlledAction.allCases`, so adding a new high-risk action or mode is no longer a casual Tuesday enum edit. It has to bring the stove controls with it.

## 2026-05-22 — The Active Wallet Key Got Its Label

`A-004` was one of those security tickets where the code was already doing the intended thing, but the paperwork had left future engineers a trapdoor. Shell selection lives in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: available after the user unlocks once, unavailable before first unlock, and pinned to this device so it does not ride along in backups or migrations.

The important distinction is that active wallet address and chain are wallet metadata, not signing credentials. The shell may need them for restoration, refresh coordination, and deep-link replay even when the device is locked after first unlock. Wallet passwords still belong under stricter credential-specific policy. The ADR and local storage policy now say that out loud, including the local-preferences reset phase, so the next audit does not have to read tea leaves from a Keychain constant.

## 2026-05-22 — Public Identifiers Got Name Tags And Exit Doors

`A-003` was a classification cleanup, not a vault migration. ENS names and Ethereum addresses are public identifiers in Auralis, so the ENS cache did not need to move out of UserDefaults just to look more serious. What it did need was a name tag in `LocalDataStoragePolicy` and a guaranteed exit door during privacy reset.

The policy table now covers the ENS cache, receipt integrity heads, gas cache, search history, and the bundled Alchemy public client key. The useful distinction is retention, not drama: ENS mappings can sit in a short-lived UserDefaults blob because privacy reset clears them; receipt heads are wallet metadata in Keychain because they tie receipt-chain state to account keys; search history is wallet metadata because public words can still reveal user intent.

The regression tests now act like a clipboard at the door. Known persisted identifiers must appear in the policy table, and a real ENS cache seeded with forward and reverse mappings must be empty after privacy reset. Public does not mean unmanaged. It means managed with the right label.

## 2026-05-22 — The Provider Error Bouncer Got A Guest List

`A-002` needed one more turn of the screw. The first sanitizer pass blocked obvious secrets and raw text bodies, but it still trusted any JSON `message` that did not look like a token, cookie, seed phrase, or private key. That left a sneaky hallway open for operational diagnostics like trace IDs and backend shard names: not secrets exactly, but still not the kind of confetti you want in public logs or error descriptions.

The classifier now works from a guest list instead of a vibe check. Only explicitly public provider messages, such as recognized rate-limit copy with public wallet addresses, can pass through. Unknown JSON messages get the same treatment as unknown raw bodies: a reason-coded SHA-256 fingerprint that lets engineers correlate incidents without publishing the provider's internals. The regression test uses a JSON envelope with trace/backend diagnostics so this exact bug cannot stroll back in wearing a clean `message` field.

Lesson learned: "not obviously secret" is not the same as "public." Audit code should make public classification explicit, especially around provider payloads where the upstream gets to choose the words.

## 2026-05-21 — Provider Errors Got A Bouncer

`A-002` tightened the Alchemy NFT error path. The important distinction stayed intact: wallet addresses and Alchemy URL client keys are public identifiers in this product, but provider response bodies are not automatically public just because they arrived over HTTPS. They can carry auth echoes, cookies, backend diagnostics, private-key shaped accidents, and assorted operational confetti that should not become app copy, route errors, receipts, or log strings.

The fix gives provider errors a small bouncer. Classified JSON envelopes can still surface safe messages, including public wallet addresses when that helps debugging. Secret-looking payloads and unclassified raw bodies get replaced with a reason-coded SHA-256 fingerprint, so engineers can correlate incidents without publishing the payload. The regression tests now check bearer/auth fields, cookies, private keys, raw text bodies, debug/localized descriptions, and the explicit allowance for public identifiers.

## 2026-05-21 — The Alchemy Key Stopped Pretending To Be A Vault Key

`A-001` closed the provider-key posture loop. The useful clarification is that Auralis' Alchemy value is a public client key in a URL path, not a wallet password or private provider credential. Treating it like a buried treasure map made the docs sound stricter than the actual Alchemy client-call model, and stricter-but-wrong documentation is how future engineers waste days building defenses against the wrong threat.

The guardrails are now pinned where they matter: provider configuration tests expect both development and production public client keys to remain in the Alchemy URL shape, while app tests make sure Release builds still run `ValidateReleaseSecrets.sh` and reject missing or placeholder values. The remaining risk is operational abuse: quotas, billing, environment mix-ups, and key rotation. That is a traffic-control problem, not a secrecy fairy tale.

## 2026-05-21 — Query Mirrors Stayed Out Of The Control Room

`CONC-004` closed the loop on a subtle SwiftData/ShellStore boundary. `@Query` is still welcome as the app's live window into SwiftData: account lists, NFT grids, token details, and AuraPlay music rows all use it exactly like a good display case. The important rule is that the display case does not get to choose which wallet is active.

The useful fix was in the account switcher. Preferred-chain edits are account metadata, so the sheet can save them through the account-store adapter. Current-chain edits are different: they change the active shell scope, refresh behavior, route reset, and deep-link readiness. Those now go through the injected shell callback instead of first poking the SwiftData row directly. We also taught the current-chain picker to compare against the same ShellStore-derived selection it displays, so a stale account row cannot trick it into suppressing a real change.

The new architecture tests are the door signs: SwiftUI `@Query` views must not own shell-selection writes, and the account switcher's current-chain path must stay routed through the shell. The follow-up fire drill now presses the actual shell action for account removal too: active removal with fallback, active removal with no fallback, and inactive removal all prove the reducer owns route reset, persisted selection, cleared selection, pending deep links, and correlation cleanup.

Lesson learned: live persistence projections are great mirrors, but the shell still owns the steering wheel. Architecture invariants need tests that press the public button, not just helpers waiting backstage.

## 2026-05-21 — The Concierge Moved Behind The Front Desk

`CONC-001` tightened the app router's job description. `AppRouter` was already the concierge for tabs, route stacks, auxiliary surfaces, and route errors, but it was relying on SwiftUI habit to keep everyone calling from the main thread. That is fine until a background callback walks into the lobby and starts rearranging navigation signs.

The fix was to make the contract explicit: `AppRouter` is now `@MainActor @Observable`. Router-focused tests now run on the main actor too, so the test suite documents the same rule the app depends on. The lesson is simple: UI state should not be protected by vibes. If a type owns navigation state, put the velvet rope where the compiler can see it.

## 2026-05-21 — Public Identifiers Are Not Secrets

The security review got a useful policy correction: in Auralis, Ethereum addresses and NFT IDs are product-visible public identifiers, not secrets wearing trench coats. They are the street addresses and catalog numbers of the wallet world. The app can show them in UI, logs, and receipts when that helps users or auditability.

That does not make the receipt sanitizer decorative. API keys, auth tokens, private keys, seed material, cookies, copied sensitive text, provider internals, and freeform error sludge still belong behind redaction or hashing. The lesson is classification beats reflex: public chain identifiers should stay useful, while actual secrets stay out of durable records and public logs.

## 2026-05-20 — AuraPlay Learned Not To Stamp The Passport Early

`CONC-002` had one last practical bug hiding behind the actor cleanup: AuraPlay marked an account as synced before the projected media rows were actually written. That is like stamping a guest's passport while their luggage is still sitting on the sidewalk. If the media write failed, the app could later believe the wallet's music library was fresh when the projection never landed.

The fix was to move the sync stamp after `replaceAll` succeeds and add a regression test with a deliberately failing media writer. Now a failed projection leaves the account unsynced, which is the honest state. The concurrency lesson is that actor boundaries protect data races, but they do not automatically protect workflow truth; ordering still matters.

## 2026-05-20 — Receipt Logging Left The Front Desk Too

The last `CONC-002` wrinkle was not in NFT fetching or music projection; it was the receipt ledger. `MusicReceiptEventLogger` had escaped the main actor only by wearing an `@unchecked Sendable` sticker, while the `ReceiptStore` protocol still required every caller to visit the front desk. That built, but it was not the clean shipping story we wanted.

The fix was to put the ledger where it already wanted to live: behind `ReceiptPersistenceStore`, a SwiftData `@ModelActor`. `ReceiptStore` is now a `Sendable` async contract, `SwiftDataReceiptStore` is a small sendable facade over the model actor, and reads/exports use `await` just like writes and resets. The music logger no longer needs a fake passport because all of its stored collaborators are honestly sendable.

The lesson is sharp: `@unchecked Sendable` is a fire exit, not a lobby. It can help during migration, but ship-ready architecture needs a named owner for mutable state. In this case the owner was already there; the public API just had to stop pretending persistence reads were synchronous UI work.

## 2026-05-19 — CONC-002 Moved Data Work Off The Front Desk

`CONC-002` is closed. The broad `@MainActor` net came off the NFT and AuraPlay service seams that were doing fetch, projection, metadata, persistence, and receipt coordination work. The front desk still stays on the main actor where it belongs: `NFTService` owns observable UI loading state, progress, errors, and refresh phases. The warehouse work no longer has to stand in that same line.

The shape is now explicit. `NFTFetcher` is an actor. AuraPlay library projection has its own actor, and SwiftData reads/writes go through `@ModelActor` stores. Metadata preparation and persistence use cases are `Sendable` service contracts. The tiny refresh timestamp cache became a lock-protected `Sendable` class because the shell needs synchronous freshness reads today; that is a small locked drawer, not a reason to drag the whole refresh pipeline back onto the UI actor.

The gotcha was the receipt recorder. Its backing `ReceiptStore` is still `@MainActor`, so making the recorder itself an actor caused a cross-actor send warning. The practical fix was an immutable `@unchecked Sendable` recorder that funnels actual mutation through the existing receipt-store boundary. Lesson: removing `@MainActor` is not a game of annotation whack-a-mole. Every shared thing still needs a real owner.

## 2026-05-19 — NFTKit Stopped Mailing Provider Errors Through The Warehouse

The final `ARCH-002` gap was not the manifest diagram. It was a tiny type living in the wrong room. `NFTPersistence` imported `NFTProviderAdapters` only so receipt logging could translate a fetch error into safe public fields. That is like making the warehouse call the delivery driver every time it needs to write a shipping label: convenient, but the dependency points the wrong way.

`NFTProviderFailure` now lives in `NFTDomain` as a portable failure value with a receipt-safe public error code. Provider adapters still own the messy classification from `ProviderAbstractionError`, `AlchemyNFTService.APIError`, and `NFTFetcher.FetcherError`; they convert raw errors into the domain value before handing failures to the receipt recorder. Persistence records the typed result and no longer imports provider adapters at all.

The new guardrail matters: `ArchitectureBoundaryTests` now fails if `NFTPersistence` imports `NFTProviderAdapters`, `ProviderKit`, `ChainProviders`, `ExplorerAdapter`, or UI modules, or if the package manifest adds the adapter dependency back. The lesson is that “one-way dependencies” are not done until the tests protect the awkward little exceptions too.

## 2026-05-19 — NFTKit Stopped Passing SwiftData Through The Loading Dock

The second `ARCH-002` pass closed the sneaky part of the boundary: provider fetching no longer hands the rest of the pipeline live SwiftData `NFT` models. That old shape was like asking the delivery driver to carry the restaurant's inventory database on every trip. It worked, but it meant the provider adapter knew too much about storage furniture.

The new border object is `NFTInventoryItemSnapshot` in `NFTDomain`. Provider adapters translate provider payloads into that plain snapshot, presentation enriches the snapshot with metadata and refresh scope, and only `NFTPersistence` turns it back into SwiftData rows. The compatibility `NFTKit` target still exists as a reduced facade, but app and feature source files now import the explicit layers they use instead of walking through the umbrella.

The guardrail got sharper too: architecture tests now fail if `NFTProviderAdapters` imports `AuralisPrimaryPersistence` or directly declares that product dependency. The lesson is that package diagrams are cheap until data types cross the border. The crossing type is where the real architecture lives.

## 2026-05-19 — NFTKit Got Actual Walls, Not Tape On The Floor

`ARCH-002` moved from floor-plan energy to real package boundaries. `NFTKit` is now a compatibility facade over four first-party rooms: `NFTDomain` for clean refresh vocabulary, `NFTProviderAdapters` for Alchemy/provider fetching and retry behavior, `NFTPersistence` for SwiftData writes and receipt-backed audit plumbing, and `NFTPresentation` for the observable `NFTService` coordinator plus user-facing failure copy.

The useful gotcha was the umbrella export. Removing `@_exported import ProviderKit`, `ChainProviders`, and `ExplorerAdapter` made a few app and test files admit what they were already using: provider configuration, token holding DTOs, and Alchemy fixture types. That is like discovering the kitchen had been borrowing the loading dock's key through a hole in the wall. The fix was explicit imports at the call sites, not rebuilding the hole with nicer trim.

The guardrail is now executable: `ArchitectureBoundaryTests` fails if `NFTDomain` imports SwiftUI, SwiftData, provider, explorer, receipt, or higher NFT layers; if provider adapters sneak in UI/persistence/presentation state; or if the facade starts re-exporting provider packages again. Refactors only count when the walls come with door sensors.

## 2026-05-19 — NFTKit Got A Floor Plan

`ARCH-002` now has an explicit migration plan instead of a one-line wish. The current `NFTKit` package is trying to be the dictionary, delivery truck, warehouse, front desk, and stage lighting all at once: domain vocabulary, provider retries, SwiftData persistence, observable refresh state, and provider re-exports all share one target.

The new plan gives each job a room. `NFTDomain` becomes the clean vocabulary, `NFTProviderAdapters` owns Alchemy/provider behavior, `NFTPersistence` owns SwiftData storage, and presentation state lives in `NFTPresentation` or app composition. The extra lesson was the umbrella export: `NFTKitPackageExports.swift` quietly lets provider packages leak through the front door, so the plan now calls out explicit imports and boundary tests as first-class work.

## 2026-05-19 — AuraPlay Receipts Moved Into The Music Room

`ARCH-005` is now implemented. The AuraPlay receipt vocabulary and logging service moved out of the app target and into `MusicFeature`, which is where the music feature's audit language belongs. The app still wires the live `ReceiptStore`, SwiftData contexts, and `AudioEngine`, but the feature package now owns the music-specific receipt contract instead of borrowing it from a hidden app folder.

The small trap was `AudioEngine`: dropping `NFTKit` was not just deleting an import, because it had been quietly getting HTTP `Retry-After` parsing through that dependency. The fix was to give playback its own tiny parser for numeric and HTTP-date retry headers. That keeps the DJ booth from asking the NFT warehouse how long to wait before retrying a download.

The guardrail is a new architecture test. It checks that MusicFeature depends on the receipt/capability contracts it actually uses, that AuraPlay receipt implementation files do not creep back into the app target, and that `AudioEngine` does not re-import `NFTKit`.

## 2026-05-19 — ARCH-003 Left The Active Board

The last loose end in `ARCH-003` was tiny but worth cleaning up: `MusicRuntime` still lived in `AppServices.swift`, even though `MusicAssembly` was already the room that built it. That is like moving the stereo into the music room but leaving the owner's manual taped to the front door. The type now sits beside `MusicAssembly.makeRuntime()`, so the file ownership finally matches the architecture story.

With that done, `ARCH-003` came off the active security and architecture ticket list. The board now reflects work that still needs decisions instead of keeping a completed refactor around as historical furniture.

## 2026-05-19 — AppServices Stopped Being The Whole Building

`ARCH-003` is now implemented: `AppServices.swift` went from a 584-line everything drawer to a thin bootstrap aggregate. The concrete wiring moved into feature-scoped assemblies: providers, receipts, accounts, shell, music, privacy, token holdings, search, home, policy, and main-tab composition each have an owner now.

The architectural win is boring in the best way. `AppEnvironment` still gives the app one obvious composition root, but it no longer personally builds every stove, sink, speaker, and cash register in the restaurant. It hands each room to the assembly that understands that room. Provider wiring stays with `ProviderAssembly`, receipt-backed recorders with `ReceiptAssembly`, shell context with `ShellAssembly`, AuraPlay runtime with `MusicAssembly`, and so on.

The tripwire matters as much as the move: `ArchitectureBoundaryTests` now fails if `AppServices.swift` starts directly constructing things like `NFTService`, `AudioEngine`, `ReceiptStores.live`, token-holding stores, privacy reset services, or policy gates again. A follow-up pass also removed the temporary `.live(...)` compatibility shims from the assembly layer, so call sites now go straight through `AppEnvironment.live.<assembly>` instead of pretending the migration scaffolding is a permanent API. Refactors only stay refactored when the codebase remembers what it learned.

## 2026-05-19 — ARCH-003 Became A Moving Plan, Not A Moving Truck

The `AppServices` split ticket was too vague for safe implementation: it said to pull the giant composition root apart, but it did not say which box each wire belonged in. That is how refactors become moving day with no labels: the couch arrives in the kitchen and nobody knows whether the lamp is missing or “abstracted.”

The ticket now names the assemblies, their owned factories, the migration order, and the guardrails. Provider construction goes to `ProviderAssembly`, receipt wiring to `ReceiptAssembly`, token holdings sync to `TokenHoldingsAssembly`, shell context and store construction to `ShellAssembly`, and so on. The important bit is that this is app-target composition cleanup, not a sneaky package migration or concurrency rewrite.

The lesson: architecture tickets need enough detail that implementation is mostly judgment plus typing, not live archaeology. A good split plan names ownership, lifetime-sensitive collaborators, tests, and what is explicitly out of scope.

## 2026-05-19 — The ERC-20 Tab Stopped Running the Loading Dock

`ARCH-004` is now implemented, which means the ERC-20 SwiftUI view finally stopped moonlighting as a warehouse supervisor. Before this pass, `ERC20TokensRootView` was pushing buttons, calling the provider, writing SwiftData rows, deciding whether stale results counted, translating provider errors, and updating banners. That is a lot of jobs for something that should mostly render the room and react to user intent.

The new `LiveERC20HoldingsSyncUseCase` owns the loading dock: native balance upsert, ERC-20 provider fetch, token replacement, coordinator-driven stale-result handling, and user-safe message mapping. The view now builds a small request, flips local loading state, awaits one collaborator, and paints the returned messages. Same user-facing behavior, much cleaner job descriptions.

The useful lesson is that refactors get safer when the old behavior moves behind a named contract before it gets clever. The tests now check the happy path, native-before-token ordering, no-op guards for empty and unsupported scopes, warning propagation, provider-error copy, persistence failures, and a source-level tripwire so token provider calls do not creep back into `MainTabERC20Views.swift` wearing a fake mustache.

## 2026-05-19 — ARCH-004 Got Its Work Order

The ERC-20 architecture ticket graduated from “this view is doing too much” to an actual implementation map. Before this pass, `ARCH-004` pointed at the smell but left the next engineer to decide where the use case lived, what it owned, which behavior had to stay identical, and how to prove the refactor did not quietly break cached holdings.

The ticket now names the boundary: SwiftUI triggers sync and renders saved rows; a focused use case owns provider fetch, native-balance persistence, ERC-20 replacement, and display-safe error mapping. It also carries the boring but important guardrails: no UI redesign, no storage schema change, no provider API reshuffle, and no new global helper bucket. A good architecture ticket should feel like a prep list in a kitchen: clear enough that another cook can start without asking where the knives are.

## 2026-05-19 — The Receipt Head Finder Put Down the Trapdoor

The receipt integrity cleanup had one of those small Swift smells that deserves respect: `current!` inside the code that decides the latest receipt head for each account. The surrounding condition made the force unwrap logically safe, but security and audit code should not ask future readers to trust a boolean maze before avoiding a crash.

The fix was to give the comparison a name. `StoredReceipt.isNewerIntegrityHead(than:)` now handles the empty-current case explicitly, then compares account sequence and global sequence in the same order as before. Same ledger behavior, fewer trapdoors. Good audit code should read like a checklist, not a dare.

## 2026-05-19 — Primary Models Took Off the Apron

`ARCH-001` is now implemented instead of merely well-described. The old problem was that `AuralisPrimaryModels` sounded like a clean vocabulary package while secretly wearing a persistence apron. Asking another package for address, chain, receipt, or tag vocabulary could also drag SwiftData schema into the room.

The fix was not to create another package. We split the existing package into two targets: `AuralisPrimaryModels` is now the clean dictionary of portable values, and `AuralisPrimaryPersistence` is the storage pantry where `EOAccount`, `NFT`, `Tag`, `Playlist`, `MusicLibraryItem`, and `SearchHistoryRecord` live. Receipt, token-holding, and AuraPlay media rows stayed with their existing storage owners.

The important trick was preserving the SwiftData class names, relationships, indexes, and uniqueness rules. This was moving shelves inside the same stockroom, not changing the inventory labels. Boundary tests now act like a health inspector: the pure target cannot import SwiftData, SwiftUI, or UIKit, and the persistence models have a clearly named home.

## 2026-05-19 — The Primary Models Package Was Wearing Two Hats

The `ARCH-001` audit ticket looked like a simple "move NFT and Tag out of the domain layer" chore until we opened the cupboard. `AuralisPrimaryModels` was not just carrying `NFT.swift` and one UI-flavored `Tag.swift`; it was also carrying the SwiftData schema for accounts, receipts, playlists, music rows, token holdings, AuraPlay media, and search history.

That matters because a package called "PrimaryModels" sounds like the neutral vocabulary everyone can share. In reality, importing it could bring along SwiftData, SwiftUI, and UIKit. That is like asking for the restaurant menu and getting handed the cash register, dishwasher manual, and paint swatches too.

The ticket now names the whole migration surface and the practical first move: move `@Model` classes into existing storage packages when there is already a clear owner, keep the rest in `AuralisPrimaryModels`, and map at storage boundaries. The warning label is important: preserve schema names and indexes first; this is a package-boundary cleanup, not an excuse to create another package.

## 2026-05-19 — External Links Learned When a Receipt Is the Ticket

SEC-010 fixed a quiet but important policy bug in the external-link handoff. Before this pass, receipt logging was treated like a nice-to-have for every destination. If the app failed to append the audit receipt, it still opened the URL. That is acceptable for a harmless help page, but it is the wrong rule for wallet-sensitive links where the receipt is the paper trail proving what the user approved.

`ExternalLinkOpenRequest` now carries an explicit audit requirement: durable or best-effort. The flow returns an outcome instead of disappearing into `Void`, which lets the app distinguish "opened cleanly," "opened but audit degraded," and "blocked because the required receipt could not be saved." NFT marketplace and explorer links are durable by default, so a broken receipt store stops the handoff instead of silently losing provenance.

The lesson is that "best effort" is not a security policy; it is a risk classification. Some receipts are like coat-check tickets. Others are like boarding passes. If the boarding pass printer is down, you do not wave everyone onto the plane and promise to write it down later.

## 2026-05-19 — The Wallet Password Moved Behind the Real Door

SEC-005 closed a security gap that looked subtle until you squinted at the threat model. The wallet password was already in Keychain, but it was protected only by the normal unlocked-device class. That is like putting a valuable key in the hotel safe but leaving the safe code taped to the front desk monitor: better than a drawer, not the hardware-backed biometric gate the feature implied.

`Password.swift` now stores the wallet password with a `SecAccessControl` built from `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `.biometryCurrentSet`. The important detail is that `kSecAttrAccessible` disappeared from the add query, because the accessibility class lives inside the access-control object. Setting both is Keychain double-booking the same room and usually gets you `errSecParam`.

The practical lesson: biometrics should unlock secrets, not booleans. If the app asks “did Face ID pass?” and then flips state, runtime hooks can lie. If Keychain is the thing returning the password only after Secure Enclave approval, there is no app-side yes/no answer to spoof.

## 2026-05-17 — Phase 2 Architecture Boundaries: Put the Walls Where the Floor Plan Said

Phase 2 was the kind of cleanup that makes an app feel less like a successful prototype and more like a system you can keep extending without flinching.

- Package boundaries got teeth. The app target now has explicit direct package dependencies, `NFTKit` no longer reaches down into `ReceiptStorage`, and `TokenStorage` no longer borrows NFT orchestration just to understand token holdings. That is the architecture equivalent of making sure the kitchen, front desk, and accounting office each have their own keys.
- SwiftData work moved out of the SwiftUI views that were doing too much. Home, Search, Profile, and Chrome now ask small service types for scoped summaries and context records instead of building fetch descriptors in the middle of view code.
- Address parsing stopped being a folk tradition. `AuralisEthereumAddress` is now the first-party canonical normalizer, which matters because wallet input, provider calls, receipts, ENS, and deep links should not each carry their own idea of what a valid address looks like.
- Local storage has labels now. `LocalDataClassification` and ADR-003 draw the line between harmless preferences, wallet metadata, and credentials. The big behavior change is active shell selection moving out of UserDefaults and into Keychain-backed wallet metadata storage.
- The Observation migration got the app onto one UI-state model. `ModeState` and `AudioEngine` now use `@Observable`, and the main views own them with `@State` instead of `@StateObject`.

The lesson: architecture tickets only count when they leave behind tripwires. The new tests are those tripwires: they fail if a forbidden package edge returns, if wallet regexes start multiplying again, if shell selection slips back into UserDefaults, or if old ObservableObject wrappers reappear in app code.

## 2026-05-17 — The Context Race Test Learned to Wait for the Doorbell

The context-service race test had a tiny but nasty timing bug: it used `Task.yield()` as if yielding meant "the first refresh definitely reached the gate now." Swift's scheduler made no such promise. Sometimes the second refresh got to the gate first, blocked behind the continuation, and the test sat there like someone waiting outside a locked apartment while the person with the key was still on the elevator.

The fix was to make the test synchronization explicit. `ControlledResolveGate` now announces when the first refresh has actually suspended, and the race tests wait for that signal before changing the wallet scope and starting the second refresh. We also gave those race tests a Swift Testing time limit so a future coordination bug fails as a test failure instead of turning the suite into wet cement.

The lesson: async tests need handshakes, not vibes. `Task.yield()` is useful for giving work a chance to run, but it is not a contract that a specific line of code has executed.

## The Big Picture

Auralis is what happens when an NFT wallet explorer, a polished dashboard, and a music player decide to share an apartment instead of living in separate apps. You connect an address, the app pulls in wallet context and NFT inventory, then turns that data into several product surfaces: home, newsfeed, gas tools, token views, receipts, and music playback.

The important part is that this is not a “show a list and call it a day” app. It has a real shell, real persistence, real routing, and a long-lived audio engine. It behaves more like a small operating system for an NFT-centric account than a toy demo.

## Architecture Deep Dive

Think of the app like a boutique hotel:

- `MainAuraView` is the front desk. It decides whether you are checking in, waiting for your room, or already headed upstairs.
- `AppRouter` is the concierge. It knows where each tab can take you and keeps the navigation mess from spilling all over the lobby.
- `NFTService` is housekeeping plus logistics. It fetches inventory, cleans stale data, and keeps SwiftData in sync.
- SwiftData is the storage room. It remembers what the network already told us so the app does not behave like it has goldfish memory.
- `AudioEngine` is the resident DJ booth. It stays alive across the app and keeps playback state coherent while views come and go.
- The home presentation logic is the lighting designer. It takes account state, pinned actions, and chain context and turns them into the polished Aura home experience.

The recurring pattern is deliberate ownership. The shell owns long-lived services, feature views receive focused inputs, and logic objects do presentation shaping instead of bloating every SwiftUI view with conditionals and formatting code.

## The Codebase Map

- `Auralis/Aura/`
  The main product shell and UI surfaces.
- `Auralis/Accounts/`
  Account persistence and wallet-facing mutations.
- `Auralis/Networking/`
  Provider abstractions, NFT fetches, ENS support, and token/gas plumbing.
- `Auralis/DataModels/`
  Shared persisted/domain models. Also, occasionally, a file that forgot what its job was.
- `Auralis/MusicApp/AI/`
  The active music experience and audio engine path.
- `Auralis/Receipts/`
  Audit-style event and receipt timeline views.
- `AuralisTests/`
  Contracts, state logic, and feature behavior checks.

If you are navigating this repo for the first time, start at `MainAuraView`, then `MainTabView`, then whichever feature surface you care about. That path gives you the real call graph instead of archaeological artifacts.

## Tech Stack & Why

- SwiftUI
  Because the app is heavily state-driven and has many presentation surfaces that benefit from declarative composition.
- SwiftData
  Because local persistence matters here, and the app wants models close to SwiftUI instead of a hand-rolled persistence layer for every feature.
- Swift Concurrency
  Because networking, refresh flows, and audio coordination are easier to reason about with structured async work than callback spaghetti.
- AVFoundation
  Because eventually somebody has to actually play the music instead of just admiring the cover art.
- Routing and presentation helpers
  Because once a shell grows past a couple tabs, ad hoc navigation state turns into a junk drawer fast.

## The Journey

### 2026-10-21 — Let the Music Sleep Until Someone Presses Play

AuraPlay used to assemble its entire playback runtime while `MainAuraView` was being initialized. That
looked tidy at the composition root, but `AVAudioEngine` can synchronously contact the system audio
server while its output node is created. In other words, opening the restaurant also phoned the concert
venue—and if that call timed out, the whole app could abort before drawing its first frame.

The shell now opens AuraPlay storage at launch but leaves the playback graph unbuilt. `MainTabView`
requests playback setup only when Music becomes the selected tab, and `MainAuraView` guards the setup so
tab reselection cannot create competing runtimes. The existing retry/error path remains intact. The useful
rule is broader than audio: infrastructure with blocking system-service initialization belongs behind the
feature boundary that needs it, not in unconditional app bootstrap.

### The event bus learned to write receipts without talking to itself

The runtime event bus already fanned activity out to Mission Control and performance tracking, but
capability revocations and expirations had no durable receipt consumer. `RuntimeReceiptObserver` now
listens for those governance-only events and appends an audit receipt. The important trap was the
feedback loop: appending a receipt publishes `receiptCreated`, which the observer must ignore or it
would become a microphone pointed at its own speaker. Event IDs are also remembered in a bounded set,
so replayed envelopes cannot create duplicate receipts and the deduplication memory cannot grow forever.

- AuraPlay Phase 3 prep, the case of the phantom wallet:
  Before starting the next AuraPlay slice, we caught the handoff docs describing a persistence graph that the code no longer has. `AuraPlayWallet`, `AuraPlayNFTToken`, `AuraPlaySchemaV1`, and `AuraPlayMigrationPlan` were still wandering through Phase 3 notes like old band members listed on a tour poster. The actual lineup is simpler: `EOAccount` is the shared account/wallet record, it stores AuraPlay sync metadata, and `AuraPlayMediaItem` is the AuraPlay-owned persisted media projection. The lesson is practical: phase docs are part of the architecture. If they point at ghosts, the next engineer burns time debugging the map instead of building the road.

- AuraPlay Phase 3 tickets, storage resolution gets a blueprint:
  We wrote down the six-ticket Phase 3 plan for storage resolution utilities: `URLResolver`, `URIScheme`, IPFS rewriting, Arweave rewriting, HTTP/data URI handling, a gateway fallback actor, and the 58-test acceptance gate. This is the little customs desk every NFT media URL has to pass through before the rest of AuraPlay tries to play it, index it, or show artwork from it. The key boundary is deliberately boring: the resolver is pure and synchronous, while network retry behavior lives one layer above it.

- AuraPlay Phase 3 alignment, don't invent a new toolbox when the garage has shelves:
  The ticket plan originally named a few objects from a generic architecture sketch: `AppConfig`, `DependencyValues`, `AppError`, `AuraPlayCore`, `AuraPlayTests`, and `MockURLSession`. The app already has different shelves for those jobs: `AuraPlayModuleConfiguration`, `MusicAssembly` / `AuraPlayDependencies`, `AuraPlayError`, the `MusicFeature` target, `MusicFeatureTests`, and `AuralisTestSupport.URLProtocolMock`. We updated the tickets so Phase 3 creates only the missing storage-resolution pieces and reuses the existing project seams where they fit.

- AuraPlay Phase 3 decisions, the resolver gets its passport stamped:
  We settled the three open implementation choices before writing code. Gateway URLs get their own `AuraPlayStorageResolutionConfiguration` because gateways are storage-resolution policy, not bundle-contract metadata. Errors flow through `AuraPlayError.mediaResolution(String)` so the feature keeps one public error surface. `URLResolver` is wired into `AuraPlayDependencies` during P3-001 even before the first caller arrives, which is like installing the outlet before bringing in the stereo.

- AuraPlay Phase 3 ships the storage-resolution customs desk:
  Phase 3 now has its real code: `URIScheme` checks the passport, `URLResolver` stamps it into an HTTPS or temp-file URL, and `GatewayFallbackChain` handles the polite knock on alternate gateway doors when the first one refuses to answer. The important engineering move is that the resolver stays boring and local: no SwiftData, no network, no hidden app-target helper dependency. Validation in this sandbox got a clean full Xcode build, clean live diagnostics, clean build-log warnings for the Phase 3 files, and a resolver snippet that exercised IPFS, Arweave, HTTP, `data:`, and rejection paths. The only wrinkle was environmental: SwiftPM tests and simulator `xcodebuild test` could not run here because the tool sandbox blocks SwiftPM sandboxing, CoreSimulator, and cache writes. That is a lab-door problem, not a resolver-design problem, but an unsandboxed local test run should still be part of release tagging.

- Receipt integrity copy contract:
  The receipt ledger now says what it can prove without puffing itself up. Local receipts are hash-chained, each account has a last-page bookmark protected in Keychain, and verification checks both ledgers against each other. That is strong local tamper evidence, like a notebook whose pages are numbered and whose last page number is locked in a separate drawer. It is not magic courtroom paperwork from a trusted third party. The product copy now says that plainly, the developer docs carry the same boundary, and tests keep the forbidden overclaim wording from sneaking back in.

- Receipt integrity end-state cleanup:
  We briefly had receipt verification acting like a helpful repair shop: if it found rows without integrity metadata, it tried to rebuild the missing chain and protected heads. That sounds friendly, but for an app that has not shipped yet it is the wrong instinct. The right pre-release contract is stricter and simpler: receipts are born with their fingerprint, previous-page link, per-account page number, and protected Keychain bookmark, or they are invalid. Verification is now a bouncer with a clipboard, not a mechanic with a toolbox. It checks the ledger, compares the Keychain heads, and refuses to mutate history while doing it.

- Receipt integrity deletion gap:
  The receipt chain had a last-page bookmark locked in the Keychain, but the verifier was only asking about bookmarks for pages it could still see in SwiftData. That meant a full out-of-band deletion of one account's receipt history could slip through because there were no remaining receipts to point the verifier at the orphaned protected head. The fix was to make the Keychain head store list every protected head and then compare both ledgers: SwiftData must have a head for every protected account, and the Keychain must have a matching head for every persisted account. Legitimate privacy resets still clear both sides together, while tampering now leaves footprints.

- Security audit closeout for SEC-008 and SEC-011:
  The receipt system now behaves less like a mutable notebook and more like a ledger with page numbers, fingerprints, and a last-page bookmark locked away separately. `ReceiptStorage` already had the integrity chain; the missing practical piece was making sure both sides of high-risk policy decisions left receipts. Denied signing/spending/transaction attempts still log `policy.denied`, and the currently allowed high-risk plugin path now logs `policy.approved`, so the audit trail records both "no" and "yes" instead of only the dramatic refusals.

- The provider-error cleanup was a reminder that redaction is not just for receipts. Gas pricing UI was still willing to repeat backend-supplied HTTP/RPC messages to users, which is how debug strings, URLs, or account hints accidentally become product copy. The fix was to keep the useful public fact ("HTTP 400" or "provider reported an error") and drop the provider prose. Good security messaging is like a courtroom summary: enough to act on, not a transcript of everything the other side said.

- AccountsFeature migration, first pass:
  The account-entry flow started moving out of the app target and into `AccountsFeature`. This pass deliberately moved the pieces that behave like good package citizens: guest pass definitions, guest pass card/carousel presentation, address pasteboard normalization, address validation presentation, and account summary presentation DTOs/presenter. Think of it like packing the front desk stationery, room keys, and check-in script before trying to move the entire hotel lobby.

- The important seam stayed put: actual account activation still lives in the app target because it touches SwiftData, ENS resolution errors, haptics, and shell callbacks. That is the right kind of restraint. A package boundary should not smuggle the whole app through a side door just because a view wants to compile.

- MusicFeature migration, first pass:
  AuraPlay finally got its first real package boundary in `MusicFeature`. The trick was not to shove the whole DJ booth into a moving box. We moved the feature vocabulary first: library scope, errors, bundle configuration, logging events, playback state/track snapshots, queue snapshots, artwork loading, library repository, and sync protocols. The app target still owns the live adapters over `AudioEngine`, SwiftData, receipts, and the existing indexer. That keeps the music package honest: it describes what the feature needs without secretly importing every wire in the building.

- The gotcha was classic migration work: the old protocols casually mentioned concrete app types like `AudioEngine.Track` and `MusicLibraryIndexRebuildResult`. Those names are convenient inside the app and poison inside a package. The fix was to introduce package-owned DTOs (`AuraPlayTrack`, `AuraPlayPlaybackPositionState`, `AuraPlayLibraryRebuildResult`) and let app adapters translate. It is the software equivalent of using a customs form at the border instead of asking the whole country to share one suitcase.

- Package boundary cleanup:
  We moved `SearchHistoryRecord`, `StoredReceipt`, `TokenHolding`, `MusicLibraryItem`, and `AuraPlayMediaItem` into `AuralisPrimaryModels` so the app target stops owning persistence models that are shared across search, receipts, holdings, and music. The lesson was simple but useful: if multiple product surfaces depend on the same SwiftData vocabulary, that vocabulary should live at the package boundary instead of hiding inside one feature folder.

- Package extraction pass: `EOAccount`, `NFT`, `Chain`, and their persistence-side traveling companions moved into `AuralisPrimaryModels`, but the interesting part was not the file shuffle. The real lesson was that `NFT` had been quietly towing a parade float: `Tag`, `Playlist`, nested SwiftData models, and media/JSON helpers all had to cross the module border too. The fix in the app target was deliberately boring and therefore good: app-side typealiases now point at the package models, which avoids a “touch fifty imports and pray” migration while keeping the package as the new source of truth. One seam stayed local on purpose: `Chain.web3EthereumNetwork` remains in the app as an extension so the package does not inherit an unnecessary `web3` dependency just to compute one adapter value.

- War story: the "old music player" was not one old view. It was a whole backstage crew still sneaking onstage through the Music tab fallback, the shell mini player, the now-playing sheet, and detail routes that still pushed `AI/V1` views even when AuraPlay owned the tab. The cleanup fix was to move the still-shipping player surfaces into `MusicApp/AuraPlay/`, delete the legacy fallback switch, and make failure honest: if AuraPlay storage or audio boot fails, Music now shows an explicit unavailable state with retry guidance instead of quietly slipping users back into the retired app.
- The lesson was memorable and mildly rude, which usually means it is true: a "migration seam" stops being a seam the minute production users can still walk through it every day. At that point it is just a side door for technical debt wearing a visitor badge.
- War story: the `NFTService` refactor split persistence and cleanup into separate seams, but three unit-test files were still speaking the old dialect. The failures looked noisy at first, but the root cause was simple contract drift: tests were still passing `shouldCleanupStaleInventory` into `persist`, and the `NFTService` test doubles no longer satisfied `PersistNFTInventoryUsing`. Fix was to update the tests to call `cleanupStaleInventory(...)` explicitly where needed and teach the stubs the new protocol shape.
- Another small trap: SwiftLint was configured tightly enough that `try! #require(...)` inside tests failed the build. Swapping those to `try #require(...)` and marking the test functions `throws` kept the assertions just as clear without leaving force-try landmines in the target.

### NFTService: Stop Making One Type Run the Entire Warehouse

This architecture ticket is the repo finally admitting that `NFTService` had become the project’s overachieving warehouse manager, forklift driver, inventory clerk, janitor, and night supervisor all at once.

- The file already contained a strong clue about the right future shape: it had a real persistence actor boundary and a real metadata-preparation pipeline, but both were still living inside the same giant service. That is like discovering your “single room” apartment already has kitchen walls drawn in pencil. The plan for `ARCH-002` is basically tracing those walls in ink.
- The important decision was to split by responsibility, not by vibe. Fetching becomes `FetchNFTInventoryUseCase`. Metadata enrichment becomes `PrepareNFTMetadataUseCase`. SwiftData writes and stale cleanup become `PersistNFTInventoryUseCase`. Freshness math gets its own `NFTRefreshStateComputer`. The remaining `NFTService` is then just the conductor waving the baton instead of also trying to play drums, violin, and bass simultaneously.
- We also chose a pragmatic migration path instead of a naming revolution on day one. Keep the shell-facing public type as `NFTService` initially, extract the real seams, prove the orchestration shape, and only then decide whether the final honest name should be `NFTRefreshCoordinator`. Good refactors separate structural change from rename turbulence whenever possible.

The lesson is one senior engineers keep relearning in different costumes: when one type owns fetch logic, transformation, persistence, cleanup, and UI freshness state, every bug starts as a group project. The best fix is not “write more comments.” The best fix is giving each concern its own room and making the coordinator earn its title by coordinating.

The implementation pass for `ARCH-002` finally made that architectural speech real instead of aspirational:

- `NFTService` is now the thin coordinator it claimed to be in meetings. It still owns phase publishing, in-flight cancellation, refresh-event wiring, and the shell-facing API, but the heavy lifting moved out into `LiveFetchNFTInventoryUseCase`, `LivePrepareNFTMetadataUseCase`, `LivePersistNFTInventoryUseCase`, and `NFTRefreshStateComputer`.
- The fetch seam now owns the awkward “did we finish the whole inventory or just a page-shaped slice of it?” decision. That matters because stale cleanup is only safe after a real full refresh. Before this split, that knowledge leaked straight into the coordinator.
- The metadata pass stopped being a pile of private helper functions hiding in a service trench coat. Base64 token-URI decode, raw metadata fallback, refresh-scope application, and deduplication now live together in one place, which is where future bugs will be much easier to pin down.
- The SwiftData write path is now its own room with the same furniture as before: the `@ModelActor` boundary survived, merge behavior still preserves local-only state like tags, stale cleanup still stays conditional, and orphaned shared models still get pruned instead of haunting the store forever.
- We also wrote the missing seam-level tests the old structure made awkward. There are now focused suites for fetch completion semantics, metadata preparation, persistence behavior, refresh-state bookkeeping, and coordinator sequencing/cancellation behavior. In other words, the tests no longer need to treat one giant service like a black-box vending machine and hope the right snack falls out.

The memorable lesson from the implementation itself: good refactors are a lot like moving a busy restaurant kitchen from one room to four connected stations. If the tickets still get out on time and nobody drops a pan, the diners just see dinner. The staff, meanwhile, finally stops bumping elbows every time one person reaches for the salt.

The first post-split bug was a perfect little architecture trap. The extracted persistence actor was rebuilding multiple fresh `NFT` graphs, each with its own brand-new `Contract` and `Collection`, and only afterward trying to canonicalize those relationships back into shared instances. SwiftData was not amused. The result was a ghost-story grade failure where save validation complained about blank `Contract` and `Collection` records with missing required fields, even though the source data looked fine.

- The fix was not “convince SwiftData harder.” The fix was to stop constructing the wrong graph in the first place.
- `PersistNFTInventoryUseCase` now resolves shared `Contract` and `Collection` models before building each `NFT`, so every new record starts life pointing at the final canonical relationship objects instead of temporary lookalikes.
- We also replaced a lazy temporary-model trick for computing scoped IDs with plain helper functions. Same result, less weirdness inside the persistence actor.
- There was a second, sneakier extraction bug hiding one layer up: bundling persistence and stale cleanup into one use-case call made the coordinator lie about its phase. On full refreshes it could publish `.cleaningUp` before persistence had actually finished. The fix was to keep both behaviors owned by the persistence use case, but expose them as separate operations so `NFTService` can still sequence `persist -> cleanup -> success timestamp` honestly.

The lesson: if shared models are part of the storage contract, resolve them before you assemble the objects that depend on them. Retrofitting identity after graph construction is how you end up hunting phantom rows at midnight.

### ShellServiceHub: Stop Letting the Front Desk Crawl Into the Boiler Room

This architecture decision was the repo finally admitting that `ShellServiceHub` had become too convenient for its own good.

- On paper, the hub looked like a polite composition helper. In practice, it let presentation code reach into account factories, provider construction, receipt logging, search history, policy gates, and privacy reset wiring. That is less “dependency injection” and more “every room in the hotel has a skeleton key.”
- The fix is not to replace one giant bag with three medium-size bags wearing fake mustaches. The decision in `ARCH-001` is to keep use-case protocols at the feature boundary when a view is triggering work, while still allowing direct injection for narrow, stable stores that are mainly being rendered. That is the sweet spot between architecture rigor and protocol cosplay.
- We also chose not to bless `AppServices.swift` as the forever-home of composition. It can be the moving truck during the refactor, but not the new house. Once the migration lands, composition code should split into shell bootstrap dependencies, feature adapters, and live builders so the next engineer does not discover a second service locator growing in the walls.
- For previews and tests, the rule is similarly pragmatic: keep `preview` and `testValue` factories as extensions in preview/test support areas instead of baking them into the main production file. Same ergonomics, less production clutter.

The lesson is senior-engineering-simple: if a SwiftUI view can casually reach into infrastructure plumbing, that plumbing is eventually going to leak into product logic. The right boundary is not “views know nothing.” The right boundary is “views know only the contracts that make sense from where they stand.”

The follow-on lesson came when the planning doc itself needed cleanup. Architecture notes that still contain conversational “I agree with both” language are fine during discovery and bad for handoff. We turned the remaining lifetime question into an explicit ownership policy with a review test and a small dependency table. Much better. A handoff doc should read like a map, not like chat logs taped to the dashboard.

### Swift Testing Meets MainActor and Throws a Chair

This was a classic Swift 6 test-target failure where the app code was innocent and the tests were the ones walking into traffic.

- `ModeState` is correctly `@MainActor` because it owns UI-facing observable state and `@AppStorage` plumbing. `ModeReceiptAugmentor.attachMode(...)` is also `@MainActor` because it reads that same shared state.
- `ModeStateTests` was still written as a plain nonisolated suite, which used to feel harmless and now gets you a compiler lecture. The result was a test build that never reached execution because the suite was calling a main-actor initializer and reading a main-actor property from the wrong context.
- The fix was intentionally small: move the suite onto `@MainActor` instead of watering down the production annotations. That keeps the app contract honest and makes the tests state their threading expectations explicitly.

The memorable lesson: when Swift Testing starts vomiting macro noise and “nothing ran,” do not immediately blame the framework. Sometimes the test suite just forgot which actor owns the room.

### AuraPlay Phase 1: The Blueprint Matters Before the Bricks

This planning pass looked simple on paper: take the AuraPlay Phase 1 ticket list and turn it into work. The catch was that the ticket set describes a brand-new app with a brand-new identity, while the actual workspace is an established Auralis repository with its own history, architecture, and shipping concerns. In other words, the blueprint arrived for a clean lot, and the lot already has a house on it.

- The first important decision was to stop pretending that "single initial commit" or "empty intentional project" acceptance criteria could be literally true inside this repo. That is not pessimism; that is engineering honesty. A plan that ignores repository reality is just a future bug report wearing business clothes.
- The resulting strategy treats the repo boundary as the first architectural question, not an administrative afterthought. Should AuraPlay be a separate repo, a new target in this repo, or merely a conceptual retrofit of Auralis? That answer changes the meaning of nearly every P0 ticket.
- We also locked the sequence around the real choke point: architecture selection. DI, logging, test ergonomics, and service wiring all want to know whether the app is going TCA or native `@Observable` first. Trying to "just start the project" without that decision is how foundation work turns into a partial rewrite by ticket four.

The useful lesson is very senior-engineer flavored: before you write the first line of "implementation," make sure the physical reality of the repository matches the story the phase plan is telling. Otherwise you are not building a foundation. You are pouring concrete in somebody else's driveway.

That said, the product direction got sharper after the first draft: AuraPlay is not a separate app after all. It is the full rebuild of the existing Music tab inside Auralis, and it is allowed to share code with the rest of the app. That changes the plan substantially:

- the right move is not "bootstrap a new app," it is "create a clean module boundary for a music rebuild inside the current app"
- the architecture question is settled up front: native SwiftUI plus `@Observable`, no TCA detour, no framework beauty pageant
- the migration risk shifts from repo bootstrapping to ownership discipline, especially around the existing audio engine and the `MusicApp/AI/` surfaces that are already live

The better analogy is no longer "build a house on an empty lot." It is "renovate the nightclub without turning the music off mid-set." You keep the shared plumbing, electricity, and exits that already work, but you still need a disciplined plan for which room gets rebuilt first and which wires nobody is allowed to cut casually.

### AuraPlay Phase 2: Build the Storage Basement, Not a Second House

The next AuraPlay planning pass had a similar trap wearing a different outfit. Phase 2 is all about persistence, search, playlists, and playback state. That kind of ticket list tempts engineers into drawing a brand-new subsystem in a vacuum, as if the existing AuraPlay seams were just polite suggestions. They are not.

- Phase 1 already gave AuraPlay a front door: `AuraPlayTabRootView`, `AuraPlayCompositionRoot`, `AuraPlayDependencies`, and the first service seams for library, playback, queue, artwork, and logging. If Phase 2 ignores those and builds a parallel dependency story, the module ends up like a restaurant with two host stands and nobody sure which one seats the guests.
- The correct shape is deeper, not wider. SwiftData belongs underneath the current module boundary, not beside it. The shell still owns `EOAccount` and `Chain`, the tab seam still constructs live dependencies, and the new `@ModelActor` services become the backstage crew moving scenery while the actors stay on their marks.
- Search had its own shiny-object danger. A persistence phase plus search tickets is exactly how “maybe we should just drop in SQL/FTS” sneaks into a plan. This repo does not need another database religion. The Phase 2 strategy stays fully Apple-native: SwiftData for storage, a trie for instant prefix work, CoreSpotlight for system-grade text retrieval, and NaturalLanguage embeddings for the “show me dark ambient driving music” flavor of query.

The memorable lesson is architectural: when you add a basement to a house that people are already living in, the smart move is to support the existing structure while you dig. You do not build a second house three feet away and hope the kitchen figures it out later.

### AuraPlay Phase 2, Wave 1: Pour the Footings Before You Decorate the Room

The first implementation wave for AuraPlay Phase 2 was intentionally unglamorous, which is usually how you know it matters.

- We added the persistence spine before adding the real music entities. That meant `AppModelContainer`, `AuraPlaySchemaV1`, `AuraPlayMigrationPlan`, and `ADR-002` landed first. It is the software equivalent of agreeing where the pipes and breaker panel go before arguing about the backsplash.
- The key discipline was dependency shape. The only new shared persistence object is `ModelContainer`, threaded through `AuraPlayDependencies`. Not `ModelContext`, not a singleton, not a “temporary shortcut” that would still be here six months later wearing a fake name tag.
- We also updated the privacy manifest for app-container file metadata access. This is exactly the sort of compliance detail that gets ignored during architecture work because it feels less exciting than models and actors, and then later turns into an App Store paperwork ambush.

The useful lesson is simple: Wave 1 should make later waves easier to do correctly, not merely possible to start. A good foundation diff feels almost boring when you read it, and much less boring when it prevents the next four diffs from becoming archeological digs.

### AuraPlay Phase 2, Wave 2: Teach the New Basement to Hold Actual Records

Wave 2 is where the storage story stops being architectural fan fiction and starts holding real shapes.

- We added the first real AuraPlay persistence graph: `AuraPlayWallet`, `AuraPlayNFTToken`, and `AuraPlayMediaItem`. The important design move was making `MediaItem` the query-friendly front desk while `NFTToken` stays closer to the raw collectible identity behind the curtain.
- The import path also became real. `LiveAuraPlayLibrarySyncService` now reads wallet-scoped music NFTs from the existing app store and mirrors them into the separate AuraPlay SwiftData container. That is the “renovate the nightclub without shutting off the speakers” move in code form: the old system still knows where the records are, and the new system now gets its own organized crates instead of borrowing stacks forever.
- The library repository learned a practical migration trick instead of a philosophical one. If AuraPlay has already mirrored a wallet into its own store, reads come from the new persisted media graph. If not, the repository falls back to the legacy indexer. That is a clean handoff ramp, not a cliff.

The memorable lesson here is that migration work gets safer the moment you stop treating “old path” and “new path” like enemies. A good transition seam is more like a bilingual host than a coup.

### AuraPlay Wave 2.5: Stop Mirroring the Same Record Twice

This cleanup was the software equivalent of realizing the stock room had both a master spreadsheet and a second spreadsheet that was just a copy with slightly different column names.

- `NFT` was already the canonical source of truth for collectible identity. AuraPlay was reading from it during sync, then persisting both `AuraPlayNFTToken` and `AuraPlayMediaItem`. That meant the feature was paying rent for two local projections when only one of them was actually serving the user experience.
- The fix was to delete `AuraPlayNFTToken` outright and let `AuraPlayMediaItem` carry the few token fields AuraPlay still cares about: contract address, token ID, and token type. Wallet sync state stayed on `AuraPlayWallet`, and the feature-specific searchable/playable projection stayed on `AuraPlayMediaItem`.
- The nice side effect is that the sync path got more honest. Instead of `NFT -> token copy -> media copy`, the pipeline is now `NFT -> media projection`. Fewer moving parts, fewer reset paths, fewer tests building fake graphs just to satisfy a relationship no screen was actually using.

The lesson is one worth keeping framed on the wall: when a feature-specific cache stops adding meaning and starts duplicating identity, it is no longer architecture. It is paperwork.

### The App Contract Still Counts When the Feature Has Barely Started

This pass was configuration work, which means it was exactly the kind of work people postpone until App Review turns into a hostage situation.

- `Info.plist` already had background audio enabled, which is the glamorous part everybody remembers because it sounds like a feature. The missing pieces were the quieter contract items: a motion-usage string for the eventual run-detection story, wallet callback URL schemes, and the list of wallet apps we intend to probe with `canOpenURL`. That list matters because iOS treats undeclared probes like a bouncer treats fake IDs.
- The deep-link setup had an extra wrinkle: the codebase already speaks `auralis://` internally for app routing tests, while the wallet-pairing requirement wanted `auraplay://`. Instead of forcing those two worlds to duel at dawn, the bundle now declares both schemes. Product routing keeps its current language, and wallet callbacks get the scheme they asked for.
- The CarPlay entitlement was the other silent footgun. An empty entitlements file looks harmless right up until device builds or future capabilities expect a real key and find a blank stare instead. We added the audio entitlement now so later CarPlay work starts from an honest target contract instead of a paper shell.
- There was also no seam for testing `canOpenURL` behavior without dragging `UIApplication.shared` directly into unit tests. The fix was a tiny protocol-backed probe type. Nothing fancy, just enough abstraction to let a mock app answer “yes, MetaMask is installed” or “no, Ledger Live is not” without turning a simple availability check into global-state theater.

The lesson is boring and very real: product capabilities live partly in code and partly in the bundle contract around the code. If those drift apart, the app can look fine in the simulator right up until the OS, device, or App Review reads the paperwork more carefully than we did.

### ENS Trust Boundaries and Corrupt Chain Data

This was a "the app is being polite while doing the wrong thing" class of bug, which is often nastier than an obvious crash.

- ENS wallet entry had a trust leak. If the live ENS provider failed, the resolver could fall back to a stale cached mapping, and the address entry flow would happily save and activate that cached address as if it had just been verified. That is like asking a receptionist to confirm your hotel room number and getting "the Wi‑Fi is down, so I guessed from last week." The fix was to require a fresh ENS verification before saving an ENS-based account and to tell the user plainly when only cached data is available.
- Persisted chain raw values also needed a reality check. A few model accessors were quietly translating unknown local chain strings into `.ethMainnet`, which made bad data look valid and could route the app into the wrong scope. We moved that behavior from "silent fallback during reads" to "detect, log, and repair when accounts are loaded," and we stopped NFT refresh persistence from re-parsing stored chain raw values when the refresh scope already knows the correct chain.
- Shell restore got a matching cleanup. The selection persistence layer stored both wallet address and chain, but restore was only really trusting the account row. That made the saved scope feel more authoritative than it actually was. Restore now validates the persisted chain and reconciles it with the account’s repaired chain state instead of carrying dead or inconsistent selection data forward.
- ENS retry behavior also got less stubborn. Being offline is not a transient mystery that needs several dramatic retries before we admit reality. The ENS client now fails fast for deterministic offline conditions so cached fallback or user messaging can happen promptly instead of after a pointless backoff ritual.

The pattern worth remembering: graceful degradation is only graceful if the app also stays honest about what it knows, what it guessed, and what it could not verify.

### Storage and Networking Hardening: Fix the Leaks, Not Just the Symptoms

This pass was a tour of the kind of bugs that do not throw fireworks during a demo and still absolutely matter before shipping.

- The first bug was a SwiftData attic problem. `NFTService` was cleaning up stale `NFT` rows, but shared `NFT.Contract` and `NFT.Collection` models could still be left behind when refreshes deleted NFTs or repointed an existing NFT at a new contract/collection. Think of it like throwing away old mail while keeping every obsolete folder the mail used to live in. The fix was to prune orphaned shared models inside the persistence actor after both persistence and stale-record cleanup, so the storage graph stops accumulating little abandoned islands.
- ENS needed a reality check too. Most of the networking stack already had explicit timeout, retry, and typed-failure behavior. The web3-based ENS client was the odd cousin showing up without that discipline. We added a bounded retry loop and per-request timeout at the client boundary itself, which keeps resolver semantics, cache behavior, and receipt logging intact while making ENS transport behavior intentional instead of hopeful.
- User-facing provider errors got a cleanup pass in the places where backend prose was still sneaking through. Native balance status, ERC-20 holdings errors, and NFT provider failures now speak in app-owned language like “provider returned HTTP 500” or “provider reported an error for this wallet and chain” instead of parroting raw backend message text into the UI. Same facts, better contract.
- The ENS cache also stopped behaving like a haunted pantry. Previously, stale entries could sit in the persisted blob forever and merely wear a “stale” sticker when read. Now the cache store has an explicit retention window and prunes expired entries as part of normal cache access and writes. The nice part is that this keeps short-term stale fallback behavior, but it no longer lets old names pile up indefinitely.
- The last fix was less glamorous and very worth doing: a handful of main-thread persistence reads were answering tiny UI questions by loading entire tables first. That is fine when the app has ten records and less charming when it has ten thousand. Receipt counts now use scoped predicates, search history uses scoped sorted fetches instead of whole-table filtering, the music indexer filters for audio-bearing NFTs at the query boundary, and `MainTabView` stopped recounting NFTs from disk when the current account already carries the synchronized count it needs.

The broad lesson: ship-readiness is usually not about one giant crash. It is about removing slow drift, ambiguous contracts, and “probably fine” networking behavior before they turn into product folklore.

### Audit Triage: Fix the Real Gaps, Not the Ghost Stories

This pass was a nice reminder that an audit list is a map, not the territory. One item said haptics were completely unimplemented. The repo disagreed: `AuraHaptics` already existed, account activation already fired success feedback, account removal already had warning feedback, and even the music surface had a stray direct `UIImpactFeedbackGenerator` call. The real bug was narrower and more interesting: the app had some haptics, but not on the interaction seams the checklist actually cared about.

So the fix stayed surgical. We taught `AuraHaptics` one more trick with a selection pulse, then wired feedback into successful chain changes and pull-to-refresh on News, Gas, and Receipts. Receipts also gained an actual refresh gesture instead of just standing there looking refresh-adjacent. This is the kind of polish work that matters because it respects the user’s action at the right semantic moment, not just whenever a button happens to be tapped.

The naming audit had a similar “ghost versus bug” shape. The provider type was already correctly Alchemy-backed; the embarrassing part was the filename. Shipping `infura.swift` full of `AlchemyGasPricingProvider` code is like labeling a kitchen drawer “spices” and keeping batteries in it. Nothing explodes, but everyone wastes time. Renaming the file to `AlchemyGasPricingProvider.swift` fixed the smell without inventing a larger refactor.

The documentation gap was the last real hole. Publicly meaningful types like `Chain`, `EOAccount`, `TokenHolding`, `NFTService`, `ContextService`, and `ShellServiceHub` had enough implicit knowledge baked into them that a new engineer was expected to read minds. We added API comments where the names carry product meaning or persistence meaning, especially around chain identity, account scope, token scope, and shell wiring. Boring? Slightly. Useful? Extremely. Good docs are like labels in a restaurant kitchen: nobody praises them during a calm shift, but chaos gets much worse when they are missing.

### The Nine-Tab Problem

This ship-gate fix was not about a crash. It was about product honesty.

`MainTabView` had grown into a nine-tab control panel: Home, News, Gas, Music, Receipts, Profile, Search, ERC-20, and NFTs. The trouble was not that those secondary surfaces were broken. The trouble was that the tab bar was advertising every internal route as if it were equally core to the Phase 0 product. That is how release chrome turns into a junk drawer.

The fix was to separate "real top-level navigation" from "still-valid auxiliary surfaces." We introduced an explicit tab-bar visibility policy in `AppRouter`, kept the release tab bar focused on the core five tabs, and moved Search, Receipts, NFT Tokens, and ERC-20 detail flows behind auxiliary presentation in release builds. Debug builds still expose everything directly, which keeps development and QA convenient without shipping the whole backstage area in the main chrome.

The useful lesson: maturity is not binary. A surface can be implemented, tested, and still not deserve a permanent seat in the public tab bar. Good release polish is often less about deleting features and more about putting each feature in the right doorway.

### The Face ID Ghost

This one was pure configuration archaeology. The ship checklist warned that Face ID might be declared without a real implementation, which is exactly the kind of App Review mismatch that can waste a day for no product value at all.

The actual codebase told a simpler story: there is no `LAContext`, no `LocalAuthentication`, no biometric policy evaluation, and no `NSFaceIDUsageDescription` anywhere in the repo-visible plist or config files. What *did* exist was an empty `Auralis.entitlements` file, which is the configuration equivalent of leaving an unlabeled key on the ring and hoping nobody asks what door it opens.

### Music Receipts: Teach the Existing Ledger a New Dialect

This pass was a good example of how architecture tickets go wrong when they confuse “new behavior” with “new subsystem.”

- The music plan wanted playlist events, dry-run facts, and music-specific policy denials. The trap would have been inventing a parallel audit trail like `MusicAuditStore` and then spending the next month pretending it was “temporary.” We did the opposite. The new code rides the exact same rails as the rest of Auralis: `ReceiptDraft`, `ReceiptStore`, payload sanitization, SwiftData persistence, and the generic timeline/detail UI.
- The new piece is a translator, not a second database. `MusicReceiptEventLogger` gives the music domain a typed vocabulary with stable dotted triggers such as `music.playlist.created` and `music.auto_organization.run`, plus one consistent payload shape. Think of it like teaching the house stenographer music notation instead of hiring a second stenographer who only follows the band.
- Playlist wiring had one subtle gotcha. The create path runs through the old `PlaylistPersistenceStore` actor, while the new receipt logger is `@MainActor`. Shoving the logger directly through that actor boundary would have been concurrency soup. The fix was to let the persistence seam return a small sendable snapshot after save, then log on the main actor afterward. Same truth, less actor-crossing drama.
- We also extended the existing `ActionPolicyGate` instead of replacing it. A blocked music action now *can* emit a second, music-shaped receipt, but the global `policy.denied` fact still lands first. That matters because the app already has one policy story; music is just adding domain detail to it, not staging a coup.
- There was no real auto-organization implementation in the active tree, so we avoided fake UI theater. Instead we added a narrow dry-run service seam that emits a receipt now and gives the future organizer a real place to plug in later. That is much better than burying “TODO: remember to log this someday” in a plan doc and calling it architecture.

The lesson is pleasantly reusable: when a product area needs richer facts, first ask whether the existing ledger is missing vocabulary or missing plumbing. Most of the time, the answer is vocabulary. Build the translator, not a second courthouse.

- The second half of the work answered the more practical question: “fine, but where are the *real* music mutations?” The answer was less glamorous than the ticket taxonomy and more useful than pretending. Playlist creation already had a live UI seam, so it now emits receipts after successful persistence. Playback and queue transitions were the other genuine shipping path, so `AudioEngine` became the active seam for `music.playback.started`, `music.playback.completed`, and `music.queue.changed`.
- The important engineering choice there was injection without global sprawl. The shell now hands the shared engine a `MusicReceiptEventLogger` after `ModelContext` exists, which lets the engine write shared receipts without learning how to build stores or containers for itself. That keeps the DJ booth playing records instead of also moonlighting as the courthouse clerk.
- We also had to be careful not to let playback receipts lie. Completion logging is tied to the track that actually finished, auto-advance is marked as such, and queue-change receipts are emitted only after the next or previous transition successfully lands. The app already had stale-load and cancellation logic; the receipts needed to respect that reality rather than write fan fiction about what “probably” happened.
- The final gap turned out to live in the AuraPlay sync seam, not in some missing future screen. The persisted-library sync already classifies playable versus metadata-only items, normalizes sparse NFT metadata, projects shared NFT rows into the AuraPlay store, and runs as a system-owned music task. So the missing taxonomy moved there: `music.media_classified`, `music.metadata_override.applied`, `music.export.created`, and `music.background_task.run` now come from the wallet-scoped sync path with one shared correlation ID. That is the grown-up version of finishing the ticket. Instead of inventing fake buttons just to satisfy an enum, we taught the code that already does the work to leave a paper trail.

So we resolved the discrepancy in the honest direction: no biometric feature, no biometric declaration, no empty entitlement stub lingering around to imply otherwise.

The lesson is straightforward: App Review cares about the contract your binary advertises, not the excuses you planned to give later. If a capability is not real, remove every trace that suggests it might be.

### The Nested-Type Cleanup That Fought Back

This one looked like a boring lint chore at first: move a few helper types out of `SearchRootView`, `NFTService`, and `AlchemyTokenHoldingsProvider`, let SwiftLint stop complaining, go home. Naturally, it was not that simple.

### Package Boundary Plan: Stop Letting One Package Pretend To Be the Whole City

This planning pass was about naming the neighborhoods before the map gets any messier.

- The big architectural tell was `AuralisPrimaryModels`. Right now it is less a tidy package and more a storage unit where accounts, receipts, NFT models, search history, and music persistence all got stacked behind the same roll-up door. That worked long enough to prove the seams existed, but it is now actively hiding the real dependency graph.
- The cleanest package turned out to be `ReceiptsCore`. The receipt system already behaves like its own courthouse: typed payloads, append-only drafts, persistence adapters, sanitizers, and generic event logging. The only thing missing was an honest address.
- `AccountsCore` is also real today, but with one important caveat: `TokenHoldingsStore` sounds like an account type because it lives in `Accounts/`, yet it is actually portfolio inventory logic wearing the wrong name tag. That one should move with NFT/token inventory, not with wallet identity.
- `AgentIdentityCore` is the ENS lane. The resolver, cache, provenance, and failure contracts are already a coherent subsystem. The product-facing profile cards and guest-pass merchandising are not identity core; they are the storefront built on top of it.
- `CapabilitiesCore`, `PolicyCore`, `OperatorCore`, and `ApprovalsCore` revealed a more interesting truth: the codebase already has those ideas, but some of them exist mostly as string literals and a few enums instead of first-class packages. That is not a reason to avoid the split. It is the reason to do it carefully. `CapabilitiesCore` should become the shared vocabulary, `PolicyCore` should own observe-mode rules, `OperatorCore` should own operator/plugin/system handoffs like external-link opens, and `ApprovalsCore` should wait until approvals are real enough to deserve more than a blocked placeholder.
- The spiciest lesson was `NFTKit`. Yes, it should exist. No, it should not be “rename `AuralisPrimaryModels` and call it progress.” That would be like relabeling the junk drawer as “cutlery” while the batteries and Allen keys are still inside. The right move is to first peel receipts and accounts out of the shared package, then carve a focused NFT and holdings package from what remains.

The senior-engineer takeaway is boring and therefore valuable: package names are promises. If a package says “core,” it should define a real domain boundary. If it says “kit,” it should contain one coherent toolkit, not half the app's civic infrastructure stuffed into a trench coat.

One correction became clear immediately after the first draft of the package map: the models already extracted into `AuralisPrimaryModels` are staying put. That changes the package strategy in an important way. The new packages are not supposed to raid the shared model warehouse and carry boxes back out again. They are supposed to form cleaner service and logic boundaries around those existing shared model types. In plain English: `ReceiptsCore` should use the receipt payload and stored-receipt models already in `AuralisPrimaryModels`, `AccountsCore` should build around `EOAccount`, and `NFTKit` should wrap the NFT and holdings stack without pretending the shared package never happened. That is a healthier architecture anyway. Re-extracting already-extracted models would just create sequel churn instead of progress.

The next sensible move after that realization was turning the package plans into real migration tickets. This is one of those senior-engineer habits that looks bureaucratic right up until it saves a week of confusion. The architecture docs say what each package means. The migration tickets say what actually moves, what must not move, what depends on what, how to validate the work, and which files are secretly two responsibilities wearing one filename. That matters a lot here because several seams are honest package candidates but dishonest files. `ModeState.swift`, `AppServices.swift`, and `ExternalLinkPolicy.swift` all need “split before move” treatment. Writing that down now is cheaper than rediscovering it halfway through implementation while the compiler throws chairs.

- **The first trap was fake simplicity**: nested helper types are easy to move and surprisingly easy to break. `NFTService.RefreshPhase` was not just an implementation detail; other views were referring to that nested type name directly. Pulling the enum out without leaving a breadcrumb broke the loading UI immediately. The fix was to keep the extracted type at file scope for cleaner organization, but restore the old API shape with a compatibility `typealias` inside `NFTService`.
- **The second trap was naming collisions wearing business casual**: a freshly extracted search presentation enum compiled fine in isolation, then helped trigger ugly type-inference fallout elsewhere. Renaming it to a more specific file-scope type avoided the generic-looking `Content` collision and kept the public surface boring again, which is exactly what you want from support types.
- **The useful pattern**: if you are refactoring for structure rather than behavior, preserve outward-facing names until you can prove nobody relies on them. Think of it like moving plumbing behind a wall: yes, the pipes can change shape, but the faucet should still be where the kitchen expects it.
- **The last twist was tooling, not code**: after the helper extraction and targeted rule suppressions were in place, Xcode’s SwiftLint build phase kept replaying the exact same warning set with stale line mappings, including warnings pointing at lines that now contain unrelated code or already-correct `.toggle()` usage. Build and tests stayed green, file diagnostics stayed clean, and the warning list still read like a time capsule. Lesson: sometimes the bug is not “fix more source,” it is “the lint invocation or issue navigator is serving cached history dressed up as fresh evidence.”

### Four Bugs, Four Different Failure Modes

This round of fixes was a good reminder that "the app works most of the time" is not the same thing as "the app is safe under stress."

- **The oversized image trap**: `NFTImageView` was using `URLSession.data(from:)`, which is wonderfully convenient right up until a hostile or absurdly large media file shows up. That API buffers the whole payload before your code gets a vote. In a feed full of user-controlled NFT metadata, that is like agreeing to let strangers wheel mystery crates into your living room before checking the label. The fix was to stream bytes instead, reject obviously too-large responses up front, and stop once the payload crosses a hard cap.
- **The invisible persistence failure**: the ERC-20 holdings screen already detected local write failures, but the empty-state UI ignored that message and showed a generic state instead. So the app knew the truth and then politely lied to the user. The fix was not another retry or logging tweak; it was making the empty-state path actually surface the storage failure when that is the real problem.
- **The query parameter that vanished into the ether**: `AlchemyNFTService` exposed `spamConfidenceLevel`, passed it into query construction, and then quietly never added it to the URL. This is the software equivalent of a light switch connected to nothing. The fix was straightforward, but the lesson matters: if an API surface promises behavior, verify the plumbing all the way to the request boundary.
- **The stale count mirage**: `trackedNFTCount` looked like live state in parts of the UI, but it was really a denormalized value with only a couple of write paths. That meant resets, restores, or cleanup flows could leave the count stale while the UI presented it as fresh truth. The fix had two parts: prefer a live count derived from persisted NFTs where the UI needs freshness, and also synchronize the denormalized field during persistence/reset flows so the stored value does not drift forever.

The common theme: the real bugs were not syntax bugs. They were trust bugs. We were trusting convenience APIs, trusting a UI branch to show the right state, trusting a parameter made it to the wire, and trusting cached metadata to stay truthful. Those are exactly the bugs that survive happy-path testing and show up later wearing a fake mustache.

- Image transport error mapping pass: this was the difference between “the internet is hard” and “we know what actually happened.” `ImageLoader` was flattening every transport failure into `.networkError`, so offline mode, timeouts, and other URL-session failures all produced the same generic message. The fix was to preserve offline and timeout cases distinctly while leaving the rest in the generic network bucket, which keeps retry behavior intact but gives the user more honest feedback. Lesson: not every network failure deserves a bespoke taxonomy, but offline and timeout almost always do because they imply different next actions.

- Receipt timeline fallback cleanup: this was a tiny diff with an outsized honesty benefit. `ReceiptTimelineRecord` was decoding stored payloads with `try?` and quietly replacing any corrupt blob with an empty payload, which meant the timeline skipped the existing corruption log path and erased useful scope/search context without leaving tracks. `StoredReceipt` already had `decodedDetailsOrEmpty()` for exactly this scenario, so the fix was simply to stop bypassing it. Lesson: duplicate fallback code is where observability goes to die.

- Account receipt durability pass: this was the same fire-and-forget smell wearing a different jacket. `ReceiptBackedAccountEventRecorder` launched a detached task for every account add/select/remove or chain-scope receipt, which meant `AccountStore` could finish its mutation while the audit write was still floating around in the background waiting to maybe happen. The good news was that the surrounding account APIs were already async, so the fix did not need gymnastics: make `AccountEventRecorder.record` async, await it inside `AccountStore`, and keep receipt-write failures non-fatal by logging them inside the recorder instead of dropping account mutations on the floor. Lesson: if you already have a structured async boundary, use it instead of sneaking background work past the contract.

- Receipt logger contract fix: this was one of those bugs where the type signature was telling a bedtime story instead of the truth. `ReceiptEventLogger` returned `Result<ReceiptRecord, Error>`, but internally it launched a detached `Task` and then immediately returned a synthetic failure every time, even when the receipt write later succeeded. That meant durable writes looked like failures and fire-and-forget writes looked like a defined contract when they really were not. The fix was to make the logger’s write methods properly async, await real persistence in async flows like context refresh and music-index rebuilds, and keep tap-driven UI actions non-blocking by wrapping the awaited logger call in a local `Task`. Lesson: if persistence is asynchronous, the API needs to admit that plainly instead of inventing a fake synchronous answer.

- ENS configuration honesty pass: this was a classic case of a fallback hiding the real fire. `ENSResolvers.makeLiveClient` was using `try?` when loading provider configuration, so a missing RPC URL and an actually broken provider config both got flattened into the same “provider unavailable” story. That made the UI sound calm while the app had no idea whether configuration was absent or invalid. The fix was to preserve those two failure shapes as `ENSResolutionError.missingProviderConfiguration` and `ENSResolutionError.invalidProviderConfiguration`, teach the unavailable client to throw the specific stored error, and pin the behavior with focused resolver tests. Lesson: graceful fallback is good, but only if it does not erase the reason the system failed in the first place.

- ERC-20 persistence scope bug: this one was a nice reminder that “invalid data” only matters if you define what invalid means in the code actually making the decision. `TokenHoldingsStore` was using `NFT.normalizedScopeComponent`, and that helper only rejects empty or whitespace scope, not arbitrary malformed wallet strings. The real ship bug was that empty account scope silently returned from `upsertNativeHolding` and `replaceERC20Holdings`, which made the UI think persistence had succeeded when nothing was written. The fix was to throw `TokenHoldingsStoreError.invalidAccountAddress(...)` for empty scope and pin that with a regression test in `PrivacyResetServiceTests`. Lesson: before you “tighten validation,” verify the real normalization contract or you will fix the bug you imagined instead of the bug users can hit.

- Newsfeed tag restoration: the “Category Selector” placeholder turned out to be pointing at a real relationship that had simply never been wired through. `NFT.tags` still exists, `Tag` still exists, and the expanded card just was not using them. We replaced the fake row with real tag chips derived from persisted tag names and colors. Classic lesson: sometimes the right fix is not “delete the placeholder,” it is “finish the plumbing the placeholder was awkwardly hinting at.”

- Final newsfeed ship trim: the expanded NFT detail card was still rendering a fake “Category / Category Selector” row marked in code as a placeholder. That is exactly the kind of unfinished UI that slips through because it does not crash and still makes the product feel half-answered. The fix was simply to remove it. Better no affordance than an affordance-shaped shrug.

- Release-readiness metadata pass: this was one of those audits where half the job was fixing code and the other half was refusing to fix ghosts. The shell boundary was missing the kind of `///` summaries that make future contributors less likely to treat `ShellStore`, `ShellServiceHub`, `ContextService`, and `AccountStore` like mysterious black boxes, so that surface now has real API breadcrumbs instead of telepathy requirements. The camera-permission scare turned out to be stale because `NSCameraUsageDescription` was already present in `Info.plist`, but it was still worth verifying before pretending it was fine. Pasteboard access also got the “show me the exact code path” treatment: Auralis reads from `UIPasteboard.general.string` only on an explicit Paste tap and writes to it only on an explicit “Copy ID” action, which means the remaining privacy work is App Store Connect paperwork, not another hidden background-access bug. We also checked the `AuraTrustLabel` colors against the app’s actual dark surface palette and confirmed the warning pill still clears contrast requirements, then cleaned up the unfinished orange-dot placeholder and the commented-out `SystemImage` dead code so the release stops shipping little pieces of “we meant to come back to this later.”
- Account receipt schema drift bug: this one was a SwiftData trap disguised as an account-store failure. `AccountReceiptRecorderTests` built a tiny in-memory schema with `EOAccount`, `NFT`, `Tag`, and `StoredReceipt`, which worked right up until `AccountStore.removeAccount(...)` started using the shared cleanup helper that also deletes `TokenHolding`, music-library rows, and search history. The crash message blamed `TokenHolding`, but the real bug was test infrastructure lying about the app’s persistence surface. The fix was to stop hand-curating the schema in that suite and reuse `PrimaryStoreSchema.schema` instead. Lesson: if a test is exercising shared cleanup paths, a “small convenient schema” is usually just future drift with better marketing.
- AuraPlay legacy-removal trust rule: we finally stopped leaving the most dangerous music migration question half-open. If AuraPlay persistence fails to open, Music must not quietly limp along in a fake “probably saved” mode. The app should show an explicit unavailable state, offer recovery actions if it can, disable any action that looks durable, and record the failure through diagnostics or receipts when that path exists. This is one of those boring product calls that saves future pain: users can forgive “temporarily unavailable” much faster than they forgive “you let me organize my library and then threw it away.”
- The other two music decisions also stopped wobbling. Playlists are staying, but they are moving into AuraPlay ownership instead of squatting forever in the AI-era folder. And the shell playback chrome is staying too, which means mini-player and now-playing need a real AuraPlay-native rebuild rather than a ceremonial deletion. Translation: the renovation plan is no longer “tear out the old room and see what feels missing later.” It is “keep the feature promises, move the plumbing, and stop lying about which walls still matter.”
- Two-container cleanup boundary bug: the next crash was more revealing than the first one. Once the test used the primary schema, `deleteAccountScopedSupportData(...)` immediately tripped over `AuraPlayMediaItem`, which exposed the real design mismatch: the helper was trying to delete AuraPlay entities from the primary store context even though AuraPlay lives in its own `AppModelContainer`. That is like the front desk trying to reorganize records in a completely different building because both places technically belong to the same hotel brand. The fix was to make the cleanup helper schema-aware with `modelContext.container.schema.entity(for:)`, so it only fetches or deletes models that are actually registered in the current container. Lesson: when persistence is split across multiple containers, cleanup code must respect those borders just as much as reads and writes do.
- Receipt-retention contract clash: after the container-boundary crash was gone, the failing account-recorder test revealed a subtler bug. Removing an account deleted all prior `StoredReceipt` rows for that address, then wrote the final `account.removed` receipt, so the history surface could prove only the ending of the story and none of the setup. Meanwhile, logout/reset still correctly wanted a full receipt wipe. The fix was to stop treating receipts as ordinary per-account support data during account removal or overwrite, while keeping `deleteAllShellSupportData()` responsible for clearing them during explicit reset flows. Lesson: audit history is not just another cache. If a receipt exists to explain that an action happened, deleting it inside the same action’s cleanup path is basically shredding the evidence on the walk back to the desk.

- Ship-readiness reality check: one review note was a genuine blocker and the rest needed a more skeptical eye. The blocker was the chrome-level context inspector. In release builds, a user could tap the gyroscope pill and open a sheet full of internals like context provenance, freshness state, and receipt-linking details. That is excellent developer scaffolding and questionable production chrome. The fix was to leave the inspector available in debug builds only, mask correlation IDs in the related receipt failure logs, and stop shipping the Home energy card's preview-only copy to release users. Same lesson three times: if something exists to help engineers debug, do not accidentally promote it to a customer-facing feature.

- Networking hardening, round two: this was the “sunny day versus real weather” pass. The NFT provider had a one-way degraded-mode latch, which meant one bad 5xx could push the app into a permanently stripped-down metadata path until restart. That is less graceful degradation and more like a hotel permanently switching to emergency lighting because one breaker tripped once. The fix was to keep degraded fallback scoped to the failing request instead of turning it into a session-wide personality change.

- Networking hardening, round three: this was the “stop lying about freshness” pass. The live shell was accidentally wiring `URLSession.shared` into providers that already had their own timeout policy, which is like buying four seatbelts and then choosing to drive without any of them buckled. The provider factory now only injects a session when we explicitly mean to override defaults. Gas pricing also learned to admit when it is showing stale cache data instead of repainting yesterday’s estimate as “updated now,” the audio engine stopped using `URLSession.shared` for remote downloads and now retries only the failures that deserve a second chance, and native-balance refreshes finally keep the useful HTTP/provider context instead of collapsing into a blank shrug. The broader lesson: fallback behavior is only trustworthy when the app can still explain what kind of fallback the user is seeing.

- Wallet Status productization: once we decided the chrome sheet was a real production feature instead of a debug hatch, the standard changed completely. A gyroscope icon plus “Context Inspector” copy is acceptable engineer bait and mediocre customer UX. The fix was not to hide it better; it was to make it act like a shipped feature. The release build now exposes the sheet, the entry pill reads like wallet status instead of a secret panel, schema-flavored and pointer-flavored labels were stripped out, and the body copy now talks about wallet details, sync state, shortcuts, and recent updates in plain language. The rule of thumb here is simple: if users can open it, they should not need to think like the app’s internal telemetry pipeline to understand it.

- The NFT fetch contract also got stricter in a good way. `NFTFetcher` used to return partial collections when later pages failed, which sounds merciful until you realize the app could then persist and present an incomplete wallet as if the refresh had basically succeeded. We changed the behavior to fail the refresh instead of smuggling a truncated inventory through the happy path. In other words: if the moving truck only delivers three rooms of furniture, do not declare the house fully furnished.

- Gas and token providers needed honesty more than optimism. The gas path was willing to hand back expired cache data after a failed refresh, and the view model would happily stamp it “updated now,” which is the software equivalent of slapping today’s date on yesterday’s newspaper. That fallback is gone. On the ERC-20 side, enrichment failures were getting flattened into generic warnings even when the real problem was authorization or provider availability. The provider now preserves those distinctions so we only degrade when the problem is truly “temporary metadata turbulence,” not “your credentials are wrong” wearing a fake mustache.

- The image loader got a similar truth serum. Non-2xx image responses were being treated like mysterious decode failures, which is how a 404 ends up pretending to be broken image bytes. The loader now recognizes HTTP status failures explicitly, so a missing image looks missing, a rate-limited host looks rate-limited, and retry affordances only show up when a retry is actually sensible.

- Keychain password storage had the classic "quietly fine until it matters" smell. The old wrapper used a background-friendly but too-permissive accessibility class, flattened load failures into `nil`, and treated delete like a suggestion instead of a checked operation. The fix was to put Keychain access behind an actor, make the production API async and throwing, default credentials to `WhenUnlockedThisDeviceOnly`, and keep raw `OSStatus` available when securityd has something useful to say. Lesson: a credential store that cannot tell the difference between "missing," "locked," and "broken" is not being user-friendly. It is throwing away evidence.

- ENS trust also became less invisible. The underlying web3 client still requires an explicit resolution mode, but Auralis now records when a network ENS result came from an offchain-enabled path instead of making every network resolution look identical. That sounds small, but trust boundaries are exactly the kind of thing that should not hide inside implementation details like a raccoon in the walls.

- Another pre-ship issue list needed the usual reality filter. Some tickets were real but needed a different remedy than the brief suggested, and some were simply overstated. `NSCameraUsageDescription` already existed, so the runtime-crash warning was stale, but the copy was wrong for the active QR wallet flow. We updated it to tell the truth: the camera is used for wallet QR scanning and playlist cover capture. That is the kind of metadata bug that looks boring right up until App Review asks why your permission prompt is talking about the wrong feature.

- The Home energy card was another honest bug hiding behind pretty UI. `EnergyCardView` had configurable inputs, but Home never supplied anything beyond `Date()`, so users always saw the same “Warming up / Morning energy” story as if the app had psychic powers and a broken watch. Instead of pretending the data is live, the card now shows a visible preview state and the call site carries a TODO pointing at the missing real data source.

- Search indexing got a small but important actor cleanup. The local search index builder was doing its dictionary-building and sorting work from a `task(id:)` path rooted on the main actor. That is fine until a wallet gets large and the search screen starts doing calisthenics on the UI thread. The fix was not “cache more view state and hope”; it was snapshot the model data into value types on the main actor, rebuild the index in a detached task, then publish the finished value back to the view. Heavy prep offstage, UI update back on stage.

- One other ticket got rejected on contact with history. A proposed optimization suggested caching `HomeTabView` derived data into `@State` so the body would stop recomputing it. That sounds tidy, but this repo already has the scar tissue: the journal has a prior regression note showing that exact pattern caused stale Home UI when the underlying SwiftData records changed without changing simple counts. In this case, “optimize the render path” was really “reintroduce an old bug with a fresh haircut.”

- The haptics pass was worth doing because the app had device feedback in one corner and silence everywhere else. Address submission, QR scan success/failure, and account switching/removal now produce lightweight feedback, but only when Reduce Motion is not enabled. Nice reminder that tactile polish should still obey accessibility instead of freelancing as “optional delight.”

- Release secrets and actor cleanup: this round was a useful reminder that pre-ship issue lists are often a mixed bag. The release-secret concern was absolutely real. Both app xcconfigs use an optional include for `Secrets.local.xcconfig`, which is convenient locally but also means CI could produce a Release archive without an Alchemy key and only discover the problem when the app crashes on launch. The fix was to add a Release build phase that fails the build if `AURALIS_ALCHEMY_API_KEY` is missing or still looks like placeholder text. Much better to fail in the factory than after the box reaches the customer.

- The `GasPriceCache` note was also real, but the proposed remedy was too dramatic. The issue was not “invent a whole shutdown lifecycle”; the issue was “actor cleanup is happening from the wrong isolation context.” Since the project already builds with Swift 6 and already uses `isolated deinit` elsewhere, the right move was the small one: switch `GasPriceCache` to `isolated deinit` so its cleanup task is cancelled on the actor executor instead of from a concurrency gray area.

- Several other scary bullets turned out to be false positives once the code got inspected instead of merely accused. `NFTFetcher` already has retry/backoff logic, the ERC-20 path already has provider retry controls, receipt/ERC-20/NFT rows already expose accessibility identifiers in active flows, and `Playlist` plus `MusicLibraryItem` were present in the codebase all along. This is a classic engineering lesson: a checklist is a lead, not a verdict.

- Persistence hardening pass: this one was less glamorous than a UI polish round and much more important. The app had a few places where local writes still happened right on the main actor, which is the software equivalent of making the cashier leave the register every time a box needs to be restocked in the back room. `AccountStore`, `TokenHoldingsStore`, `SearchHistoryStore`, and `SwiftDataReceiptStore` now push their mutations through model actors so saves happen off the UI path instead of freezing the front desk while SwiftData does paperwork.

- The receipts path also stopped treating one corrupted blob like a building-wide fire alarm. `StoredReceipt` used to throw on bad payload decode, and several `SwiftDataReceiptStore` read APIs would happily propagate that failure outward. Result: one rotten `detailsData` value could poison export and timeline reads for everything around it. The fix was to fail soft for decode-at-read time, log the corruption, and fall back to an empty receipt payload instead of taking the whole receipt surface hostage.

- Privacy reset needed one more truth-in-advertising pass. The reset service dutifully cleared persisted selection and local support data, but the live `ShellStore` was still holding the active wallet in memory like a bartender keeping your tab open after you already paid. That meant “Clear Local Privacy Data” could succeed and still leave the app visibly signed in until the next launch. The fix was to keep `PrivacyResetService` focused on storage cleanup and have `SettingsView` explicitly tell the shell to log out once the reset finishes. Storage clears the shelves; the shell turns off the lights.

- ENS cache reset had a sibling bug hiding in the wiring. The app behaved like there was one global ENS cache, but the live resolver factory and the reset service were each quietly constructing their own `ENSResolutionCacheStore`. Clearing one store while another resolver kept its own in-memory snapshot is like changing the whiteboard in the hallway while the person in the room keeps reading their private notebook. The fix was to share one cache-store instance at the production composition layer and lock that seam down with a boundary test proving a reset empties the live resolver’s cache immediately.

- Privacy reset had one more hole in the hull: it cleared search history, receipts, token holdings, and caches, but it left persisted `NFT` rows and `MusicLibraryItem` rows sitting in SwiftData. That meant the app could say “local privacy data cleared” while the device still held the wallet-derived inventory the rest of the product is built around. The fix was to add a dedicated SwiftData-backed derived-data reset seam and make the privacy reset call it alongside the other storage cleanup, with a regression test that seeds both models and proves they are gone afterward.

- Privacy reset then needed a second pass, because “we split the work into services” is not the same thing as “the overall reset tells the truth.” The nasty edge case was a later phase failing after earlier destructive work had already committed. That is like a hotel saying “your room was never touched” after housekeeping already threw out half the minibar. The reset flow now has explicit phases: transactional wallet data first, support caches next, AuraPlay persistence after that, and local preference cleanup last. The transactional SwiftData phase still rolls back atomically on failure, while later failures now report exactly which phase blew up, which phases already completed, and that the operation is safe to retry. We also pinned the retry contract with a test that forces AuraPlay persistence to fail once and then proves a second reset run finishes cleanly instead of getting stranded in “half-cleaned forever” limbo.

- The test suite also got a reality check on schema drift. A few SwiftData tests were building tiny hand-picked in-memory schemas that were “close enough” until production code started deleting support data those tests had quietly omitted. That is how you end up with a passing test that has never actually exercised the live graph. The fix was to stop letting each suite freelance its own container and instead point the important destructive-flow tests at a shared `TestModelContainers.primary()` helper that mirrors `PrimaryStoreSchema` exactly. It is the testing version of using the real floor plan instead of sketching a smaller house on a napkin and claiming the evacuation drill passed.

- SwiftData V0 cleanup pass: this one was about trimming waste, not inventing a grand persistence doctrine. `SearchRootView` had been listening to every `ModelContext.didSave` in the process, which meant one save anywhere could make local search rebuild like an over-caffeinated intern hearing a doorbell. That observer now only reacts to the view’s own context. Newsfeed search also stopped doing three separate store fetches and then filtering the live query again in memory; it now issues one scoped fetch with a combined predicate and a bounded limit. On the view side, Home and Profile no longer keep full live NFT/token arrays around just to say “you have 7 things,” the shared NFT detail screen now asks SwiftData for the specific row it wants instead of hauling the whole shelf into the room, and the music library view stopped live-observing the entire scoped NFT set when it only needed resolvable music items for the current library. Finally, AuraPlay cleanup stopped scanning every persisted token row just to remove a few wallet-scoped ones. The lesson is delightfully unromantic: a V0 app still benefits from not making the database do cardio for no user-visible reason.

- SwiftData hardening for the active shell and AuraPlay was one of those bug hunts where the most dangerous problems were not flashy crashes. They were quiet lies. Removing an account used to clear some wallet-scoped rows but leave others behind, which is the persistence equivalent of moving out of an apartment and discovering you still pay for the parking space and the cable box. The shared cleanup helpers now purge receipts and music-library rows alongside holdings and search history, and logout clears the active shell support data instead of pretending that only NFTs and tags count as “local state.”

- Search also got a useful correction in philosophy. The old `SearchRootView` kept broad live `@Query` collections for accounts, NFTs, and holdings, then rebuilt an in-memory index whenever those arrays twitched. That works fine right up until a real wallet shows up with enough inventory to make the main actor sweat. The better move was not a cleverer cache; it was less live baggage. The screen now fetches scoped snapshots when it needs them and lets the parser work from those values, which is more like packing for the trip you are taking instead of dragging every suitcase you own through the airport.

- The music/NFT persistence path got the same “do less surprise work” treatment. AuraPlay sync and library indexing were fetching full NFT graphs and then lazily poking relationships one by one like somebody opening every kitchen drawer while cooking. Those fetches now prefetch the relationships they actually use, and the AuraPlay repository stopped minting a fresh `ModelContext` every time it wanted a count. One context, one read lane, fewer side quests.

- The final cleanup pass fixed a classic scalability footgun in `NFTService`: every scoped refresh ended by scanning the whole store to decide whether shared contracts and collections had become orphaned. That is the database version of sweeping the entire building every time one room gets rearranged. Because contract and collection identities are already chain-scoped here, the prune step now only inspects the affected chain and the candidate shared rows touched by that refresh. Same correctness, much smaller broom.

- One follow-up bug was a reminder that “privacy reset” and “logout cleanup” are not automatically the same thing just because they sound equally destructive. Account removal and logout were wiping the legacy music rows but leaving the newer AuraPlay wallet graph behind, which is like shredding the paper guest list while the VIP list still sits in the iPad at the front desk. The fix was to treat AuraPlay’s persisted wallet/token/media graph as first-class shell support data and clear it alongside receipts, holdings, history, and the older music cache.

- Search needed a second pass too. Moving away from heavyweight live `@Query` collections was the right performance call, but the first version overcorrected and lost the “stay fresh while I’m looking at it” behavior. The repair was not to crawl back to giant live arrays; it was to let the screen keep its snapshot-based indexing and listen for `ModelContext.didSave` events while open. Same lighter memory footprint, but now the shelf gets re-scanned when somebody actually puts a new book on it.

- A tiny testing cleanup earned its keep as well: one fixture helper had a hidden `try!`, which is the kind of shortcut that sits quietly until lint or CI decides today is the day for honesty. Converting that helper to throw normally kept the file explicit about failure without changing the test intent. Small change, better contract.

- Search history needed a quieter architectural cleanup: one persistence domain had somehow ended up with two people holding the keys. `recordCommittedQuery()` already wrote through a `@ModelActor`, but `removeEntry`, `clear`, and `clearAll` were still deleting rows directly from the main-actor `ModelContext`. That split ownership is how tiny convenience shortcuts turn into “why does this store have two mutation rules?” six weeks later. The fix was simple and worth doing: reserve `SearchHistoryStore` for read snapshots and async forwarding, and route every mutation through `SearchHistoryPersistenceStore`. One write owner, one set of transactional rules, much less future confusion.

- Two query-shape fixes landed in the same spirit: stop asking SwiftData for the whole pantry when the UI only needs a snack. Home’s receipt preview was holding a live scoped query for the entire timeline and then taking `.prefix(5)` in memory, which is the data-layer equivalent of unloading the whole truck to hand someone one grocery bag. That now uses a `FetchDescriptor<StoredReceipt>` with the same scope predicate, the same sort order, and `fetchLimit = 5`.

- ENS search had a more subtle scaling smell. `SearchRootView` was fetching every account with `name != nil` and then doing exact lowercase matching in Swift, which works fine until “has a name” turns into “has thousands of names.” The fix was to teach `EOAccount` a persisted `normalizedName` field, index it, and keep it synchronized whenever `name` changes. Search can now fetch exact ENS matches by equality instead of sweeping the whole named-account set into memory and squinting at it afterward.

- That ENS/search fix immediately found the classic follow-up trap: a new persisted field is only “done” when old rows know how to live with it. Existing accounts on disk did not have `normalizedName`, which meant exact ENS fetches could become technically correct and practically invisible. We folded the repair into the same load-time hygiene pass that already fixes stale chain values in `AccountStore`, so older persisted accounts backfill their normalized search key the first time they are read. Same story on the Home receipt preview: the first optimization trimmed the fetch to five rows but accidentally gave up live observation by doing a plain `modelContext.fetch()` inside a computed property. The corrected version uses descriptor-based `@Query` with `fetchLimit = 5`, which is the nice middle ground: small result set, still live, no “wait, why didn’t the UI update?” mystery.

- Provider startup and retry behavior got a realism upgrade too. `AuralisApp` was using `preconditionFailure` when provider configuration was missing, which is fine if your app is a unit test and less fine if it is a shipped product. Launch now degrades instead of detonating. On the fetch side, `NFTFetcher` had retry machinery but still refused to retry provider 5xx failures and generic HTTP server errors, which is like installing a backup generator and then deciding not to use it during an actual outage. The retry policy now gives transient server-side failures another chance, which is much closer to the resilience story the surrounding code was already trying to tell.

- Image loading hardening: this was a good example of the difference between “an issue was reported” and “the issue is real.” Some of the checklist items were stale on arrival, but two image-loader bugs were absolutely real. `ImageLoader` could fall into a permanent-looking error state after one transient network miss because the view had no in-place retry path, and oversized payloads were being funneled through `try?` into the same bland `.invalidData` bucket. The fix was intentionally surgical: add a retry affordance only for retryable network failures, preserve the explicit oversized-file failure mode, and lock the related tests to serialized execution so the shared URLProtocol mock stopped sabotaging its own evidence.

### SwiftData Audit Remediation: Stop Treating the Storage Room Like a Junk Closet

This was one of those passes where the app already looked serious, but a few persistence seams were still acting like they expected a friendly demo environment instead of a real user with a long-lived store.

- The first fix was the app-launch survival instinct. `AuralisApp` used to treat a primary SwiftData load failure like a fire alarm wired directly to `fatalError`. That is fine until a migrated store gets weird or the local file goes sideways. The new behavior is much more adult: log the failure, fall back to an in-memory container, and show a visible warning banner so the app admits that today’s memory is a whiteboard, not a filing cabinet.
- The NFT graph got a custody hearing. `NFT.Image`, `NFT.Raw`, and `NFT.AcquiredAt` are owned children, but the schema had been relying on implicit relationship behavior while the cleanup path only manually pruned shared `Contract` and `Collection` rows. That is how orphaned data starts breeding in the attic. The relationships are now explicit about cascade ownership, and the shared-model cleanup code finally matches the actual ownership model instead of hand-waving at it.
- Receipts stopped reading the whole diary just to answer one question. `ReceiptTimelineView`, `ReceiptDetailView`, and the wallet-status sheet were all observing broad `@Query` result sets and then filtering in memory. That works until the receipt table gets old enough to vote. Those screens now fetch only the scoped records they actually need, which is both faster and less likely to repaint half the UI because one unrelated receipt changed across the room.
- Undo finally became real instead of theoretical. Because the app installs a prebuilt container, the correct move was not a magical scene modifier overload; it was attaching an `UndoManager` to the primary container’s `mainContext` and then making user-facing destructive flows stop sneaking through background model actors when undo semantics matter. Playlist deletes and search-history clears now go through the main context, which means the app’s “eraser” actions finally use the same desk the undo ledger is sitting on.
- Preview stability also got a reality check. A few previews were creating partial containers with just `Playlist.self`, which is the SwiftData version of building a dollhouse and forgetting the staircase. We introduced `PreviewModelContainers` so previews use real in-memory schemas for both the primary store and AuraPlay store. Less “works on my canvas,” more “actually matches the production graph.”
- The last cleanup was the performance-and-boundary sweep: account listings now sort in the fetch instead of in memory, tracked NFT counts use `fetchCount`, NFT refresh snapshots stop loading every contract and collection in the store when only one chain matters, and the playlist persistence actor no longer accepts live `NFT` models across the actor boundary. That last one is worth remembering because actor isolation bugs are like loose floorboards: they may not drop you today, but they absolutely know where you walk.

The lesson from this whole pass is very warehouse-manager coded: production persistence is not just “we saved some rows.” It is crash behavior, ownership, query scope, preview honesty, and not letting every feature rummage through the same boxes from the wrong side of the room.

### SwiftData Truth Serum: A Relationship on Paper Is Not a Cleanup Strategy

This bug was the persistence version of a fake emergency exit painted on a wall.

- `EOAccount` had a nice-looking `nfts` relationship with `.cascade`, which *sounds* like deleting an account should also delete its NFTs.
- The real app never actually uses that relationship to scope NFT ownership. NFTs are persisted and queried by `accountAddressRawValue` instead.
- That meant removing or overwriting an account deleted the account row and left the wallet’s NFT rows behind like forgotten luggage in the lobby.

The fix was not to write a more inspirational comment about cascade rules. The fix was to make `AccountPersistenceStore` explicitly delete every `NFT` whose `accountAddressRawValue` matches the normalized account address before deleting or overwriting the account row.

The regression coverage also taught a second lesson. A first attempt to prove the fix in `AccountStoreTests` ran straight into a SwiftData fixture quirk around ad hoc NFT graph insertion. Rather than pretend that harness fight was the same as the production bug, the regression was moved into `PrivacyResetServiceTests`, where NFT fixture persistence was already proven to work. That is a very senior-engineer move: when a test harness lies to you, stop arguing with it and relocate the proof to firmer ground.

The sticky lesson: **schema declarations are contracts, not magic spells**. If your live write path uses string scope and not the declared relationship, the cleanup logic has to follow the live write path too.

- AuraPlay reset learned the same lesson from the opposite direction. The app already had a dedicated AuraPlay SwiftData store, but privacy reset was clearing it by deleting SQLite files underneath a still-live `ModelContainer`. That is the persistence equivalent of yanking the floorboards out from under someone who is still standing in the room. The repair was to make the normal path delete AuraPlay rows through the live container with a model actor, then keep the file-deletion service only as a fallback for the special case where the container never came up in the first place. The regression test matters because it proves the part users actually feel: reset, stay in the same launch, write new AuraPlay data again, no weird ghost state.

- The main app store also graduated from “trust me, SwiftData will figure it out” to an explicit versioned schema and migration plan. Before the fix, `AuralisApp` installed the primary store with a raw list of model types, which works right up until the day the schema changes and you discover your migration story was written in invisible ink. The app now builds its root `ModelContainer` manually with `AuralisPrimaryStoreSchemaV1` and `AuralisPrimaryStoreMigrationPlan`, then injects that container into the scene. There is only one schema version today, which is perfectly fine. The important part is that the runway exists before the next migration emergency, not after.

- Playlist persistence got its own quiet hardening pass too. The code already treated `Playlist.id` like a primary key, but the schema was still basically shrugging and hoping nobody would ever save two rows with the same UUID. SwiftData’s unique semantics are slightly sneaky here: duplicate IDs do not explode, they coalesce into one stored row. That is still exactly what we want, because the important invariant is “one persisted playlist per identifier,” not “a dramatic exception was thrown.” At the same time, `tracks` stopped being an implicit relationship and became an explicit one with `.nullify`, which is the correct deletion story for a playlist that references NFTs it does not own.

- The indexing and query pass was the classic performance version of tightening bolts before the bridge gets busier. Search history, receipts, music library rows, and the AuraPlay persistence models now have compound `#Index` definitions that match their real scope and sort predicates instead of relying on full scans as data grows. The accompanying count-path cleanup also stopped several hot code paths from fetching whole model arrays just to ask “how many?” or “does one exist?” SwiftData has `fetchCount`; the grown-up move is to let the store count its own shelves instead of dragging every box into the aisle first.

- Bulk delete APIs earned their keep in the final cleanup round. A few reset paths were still fetching every row into memory only to delete them one by one, which is the database equivalent of emptying a warehouse by carrying each crate through the front office. Those paths now use store-backed bulk deletes for token holdings, receipts, search history, derived NFT/music support data, and live AuraPlay rows. Same behavior, less pointless lifting.

- Pinned-actions corruption handling: `HomePinnedItemsStore` had a classic “recovery” bug that was really a data shredder in a polite hat. If stored pinned-item JSON became corrupted, read paths logged the decode failure and returned `[]`, which was tolerable for display, but the next toggle write would happily overwrite the bad blob with a fresh array and make the old state unrecoverable. The mutating path now fails closed with a real store error instead of treating corruption as an empty set. That is the safer engineering instinct: when local state smells wrong, do not casually rewrite history.

- Tiny pre-ship cleanup, useful lesson: one of the earlier “safe” fixes turned out to be too severe for real product behavior. `HomePinnedItemsStore` had been changed to fail closed on corrupted pinned-item JSON, which protected the old blob but also meant the user could get stuck unable to pin or unpin anything until local storage was manually wiped. We changed the mutation path again so it now clears the corrupted blob, logs the repair, and writes fresh state on the next toggle. That is the better balance here: preserve safety, but do not leave the user trapped in a permanently broken preference screen because one `UserDefaults` value went bad.

- Gas freshness honesty also got one more polish pass. The gas provider already distinguished stale fallback data, but warm in-memory cache hits were still being reported upstream as `.live`, which is yesterday’s leftovers wearing a chef hat. The provider now reports a dedicated cache source and the view model treats both fresh-cache and stale-cache results as cached presentations instead of pretending they came straight off the wire.

- Another pre-ship review pass had a similar theme: some scary-looking checklist items were stale, and some were absolutely worth fixing. `NSCameraUsageDescription` was already present, and the privacy-manifest worry around `CryptoKit` hashing turned out to be a false alarm after checking Apple’s current required-reason API categories. But `GuestPassCard` really did run a perpetual shimmer with no Reduce Motion escape hatch, so the card now respects `accessibilityReduceMotion` instead of insisting every user wants the same amount of motion. That is one of those bugs that can hide in plain sight because the animation looks “nice” right up until it makes someone feel awful.

- The loading surface got a small but important copy cleanup too. `NFTNewsfeedLoadingView` was speaking fluent developer status message: “Fetched X NFTs. Parsing metadata before save.” Technically true, product-wise clunky. The wording now sounds like an app talking to a person instead of a progress log talking to another progress log.

- The Chrome context inspector needed the same intervention. It had quietly drifted into “developer basement panel” territory, showing raw provenance strings, a schema version token, and clipped correlation IDs as if normal people wake up hoping to compare UUID fragments over coffee. The fix was not to remove the signal, but to translate it: provenance now speaks plain language like “Loaded from cache” or “Freshly fetched,” the version area is framed as app version info instead of schema jargon, and the refresh action now says what it actually does for the current wallet scope.

- The receipts timeline also got a render-path cleanup. `ReceiptsRootView` was rebuilding its decoded receipt records and filtered snapshot straight from `body`, which is exactly the kind of thing that works fine until a timeline gets large and SwiftUI starts asking for fresh values more often than you expected. The decoded snapshot is now refreshed from a keyed task into local state, so the view body mostly consumes prepared data instead of doing all the sorting and filtering work inline.

- One more small polish fix landed in the external NFT links. The OpenSea and explorer buttons were using hardcoded hex gradients, which is a fast way to get a button that looks “branded” in one context and weirdly out of place in another. Those buttons now lean on semantic app colors instead of frozen hex values.

- Networking hardening pass: this one was a good example of how “works on a sunny day” is not the same thing as “ship-ready.” The ERC-20 provider had pagination loops that trusted the backend like an overly optimistic intern. One repeated cursor or one endless stream of empty pages and the sync could hang forever. We added explicit stall detection, then taught the provider to admit when enrichment metadata failed instead of quietly serving placeholder rows with a fake smile.

- The RPC path got the same reality check. Native balance loading used `URLSession.shared`, took one swing, and if it missed, `ContextService` basically shrugged and erased the balance from the snapshot. That is not resilience; that is amnesia. The provider now has explicit timeout and retry policy, `ContextService` reuses the last balance for the same wallet/chain scope on refresh failure, and both RPC clients now read JSON-RPC error envelopes instead of pretending every HTTP 200 is a happy ending.

- Another useful lesson from this round: test fallout is often the most honest reviewer in the room. Changing `tokenHoldings(...)` from “array only” to “holdings plus warning” immediately surfaced every place the repo had quietly encoded the old contract. Fixing those tests was not bookkeeping; it was the proof that the new behavior was actually wired end to end.

- Another ship-readiness pass was a good reminder that issue lists need source control, not just confidence. One claimed blocker said the app would crash on camera permission because `NSCameraUsageDescription` was missing; the bundle already had the key. One claimed dead branch in the loading UI said `progressValue < 0` was impossible; the current code still allows negative `itemsLoaded`, so that branch is very much alive. The real bug was `ShellStore`: it stored an in-flight refresh task while that task captured the store strongly, which is the classic “I locked myself in the room from the inside” retain cycle. The fix was to let the task hold the refresh coordinator directly and only talk back to the store weakly when the refresh finishes, then pin that behavior with a test that drops the last strong reference while a refresh is suspended and proves the store can deallocate anyway.

- The next cleanup pass was less about one crash and more about honesty in the UI and honesty in the code layout. `ProfileCardView` and `HomeTabView` were carrying their own prompt-generation recipes plus ENS display resolution, which is a bit like asking the waiter to also butcher the fish and tune the piano. The logic now lives in small helper types so the views mostly handle state and rendering while the deterministic artwork recipes stay testable and reusable.

- The News feed also stopped copying NFT IDs like a pickpocket. Hitting “Copy ID” now shows a visible confirmation pill and success haptic instead of silently stuffing text onto the pasteboard. At the same time, the touched Home, Profile, Energy, and Newsfeed surfaces moved more visible copy to `String(localized:)`, and the Home energy card is no longer trapped behind `#if DEBUG`. It now ships as an explicit preview card, which is much better product behavior than a feature-shaped ghost only developers can see.

- Another pre-ship pass turned up a nice example of why visual bugs can be more dangerous than they look in code review. `ProfileCardView` had the correct avatar image path and the correct fallback icon path, but the fallback icon lived in an unconditional overlay `else` branch. Result: users with a perfectly loaded avatar still got the generic person glyph stamped on top like the app did not trust its own success. The fix was tiny and absolutely worth it: only show the fallback icon when there is no avatar image.

- The guest-pass shimmer had a smaller but more subtle problem. `GuestPassCard` started its infinite border animation from both `onAppear` and `onChange(of: accessibilityReduceMotion, initial: true)`. That is the sort of duplication that looks harmless until motion settings change mid-session and you realize you may have launched two forever-animations that both think they are in charge. We cut it down to one source of truth and let the accessibility-aware `onChange` own the behavior.

- The newsfeed scope got a defensive seatbelt too. `NewsFeedListingView` builds a SwiftData `@Query` from the active account and chain during initialization. That can be okay if the parent view is always rebuilt with a fresh identity, but tab containers are notorious for keeping children alive longer than your intuition wants. Instead of betting the feed on lifecycle folklore, the parent now gives the listing an explicit scope-based `.id(...)`. New wallet or new chain, new listing identity, new query. Boring and reliable is exactly what you want there.

- The failing `HomeTabLogicTests` suite turned out to be a tidy little logic trap in the aurora prompt builder. `HomeAuroraArtworkSupport` correctly computed `"subtle star patterns"` for invalid wallet input, then quietly threw that value away by only appending the pattern atom inside the valid-address branch. That is the kind of bug that makes a fallback path look implemented while still never being reachable. The fix was to append the pattern atom unconditionally and keep the address-signature token gated to real wallet input.

- Swift Testing macro gotcha: one failing test compile turned out to be two separate splinters that looked like a forest fire. Re-enabling the `todo` SwiftLint rule immediately blocked the test target on a leftover `TODO` comment in `HomeTabView`, which is a nice reminder that lint rules are only useful if the codebase can actually live with them. Then `ProviderAbstractionTests` started producing a dramatic pile of macro-generated `@const` noise plus one real concurrency error. The real bug was a `#expect(throws:)` closure returning `[NFT]` across a `sending` boundary instead of discarding the value, and the suite declaration was also the only one written inline with `@Suite`, which did not help readability or diagnosis. Once the suite was normalized and the throwing expectation stopped trying to smuggle actor-isolated data through the macro, the test compile went back to behaving like a grown-up.

- Another Swift Testing smoke bomb showed up in `AccountStoreTests`. Xcode sprayed the test target with `@const` and `@section` macro errors, which looked catastrophic and were mostly theater. The real issue was three `#expect(throws:)` closures returning `@MainActor` values like `EOAccount` and `AccountRemovalResult` instead of `Void`. Swift Testing tried to move those results through a `sending` boundary, the compiler quite reasonably objected, and the macro expansion then covered the walls in misleading debris. The fix was gloriously boring: assign the async results to `_` inside the throwing expectations so the closures only prove the error contract and do not try to carry actor-isolated payloads anywhere.

- Bug hunt: the home avatar fallback looked harmless until the math got audited. `ProfileCardView` was choosing one of eight `testProfile-*` assets, but the asset catalog only had seven. That meant one out of every eight deterministic fallbacks quietly disappeared into `nil`. The fix was simple and surgical: bind the selection logic to the real asset count instead of an imaginary eighth image.

- Another quiet gremlin lived in the home prompt caches. Both `HomeTabView` and `ProfileCardView` were evicting `Dictionary.keys.first`, which feels like "oldest" if you squint at it long enough, but Swift dictionaries do not promise LRU semantics. The cache now keeps explicit insertion order so eviction is predictable instead of vibes-based.

- Preference persistence got a sharper edge. `HomePinnedItemsStore` used to log JSON encode failures and move on as if the pin succeeded. That is the software equivalent of nodding confidently while dropping the package in a ditch. The store now throws so callers can surface the failure instead of lying to the UI.

### SwiftUI Pre-Ship Cleanup: The Bugs That Were Real, Not Just Loud

This pass was a good reminder that not every pre-ship checklist item deserves equal panic. A few reports looked scary but turned out to be either stale, speculative, or already contradicted by the repo. The worthwhile fixes were the ones tied to concrete code paths with clear downside.

What actually got fixed:

- `ImageLoader` stopped minting a brand-new `URLSession` for every image cell. In a scrolling feed, that is like giving each shopper their own grocery store instead of sharing carts and checkout lanes. The loader now uses one reusable default session with the same timeout policy, which keeps connection pooling intact and avoids needless session churn.
- `NFTImageView.swift` kept its synchronous cache fast path so already-cached images can appear immediately in reused cells, while image fetches stopped using `URLSession.shared` and now run through an explicit session with request/resource timeouts. That is the difference between “eventually this cell might load” and “fail fast enough that scrolling still feels sane.”
- `HomeTabView` dropped an unnecessary `AnyView` wrapper around the sparse-state section. This was not a dramatic crash bug, but it was a real structural-diffing tax for no gain. SwiftUI already knows how to handle that conditional when you let it.
- `HomeTabView` and `ProfileCardView` were both carrying prompt caches in `@State` dictionaries with no eviction. That is fine for five minutes and questionable for a long session. Both caches are now capped so the app does not quietly turn deterministic prompt generation into a memory souvenir collection.
- `GalleryGrid` now cancels the previous regenerate task before starting a new one, and it also cancels on disappear. Before that, repeated taps could create a small swarm of overlapping image-generation tasks, which is exactly the kind of bug that makes a UI feel “heavy” without leaving a neat stack trace behind.

The useful lesson here: a good ship review is not “fix everything anyone can imagine.” It is “separate real defects from architectural opinions, then fix the ones that can actually hurt users or destabilize the release.”

### Dead Code Sweep

We removed four confirmed-unreferenced UI leftovers after a project-wide reference audit:

- `Auralis/DataModels/TagViews.swift`
- `Auralis/Aura/Auth/LoginTitleView.swift`
- `Auralis/Aura/Newsfeed/ConnectWalletView.swift`
- `Auralis/MusicApp/AI/V1/DetailView.swift`

This was a nice reminder that “file exists” is not the same thing as “feature exists.” `TagViews.swift` was the most interesting one: it looked substantial, but the entire view stack was orphaned. It was basically a fully furnished apartment with no doors leading into it.

We validated the cleanup with a full project build, which passed. That matters because dead SwiftUI can still be accidentally wired through previews, test helpers, or stale project references. In this case, the build agreed with the grep pass: the code was just sitting there, haunting the place.

### Dead Code Sweep, Round Two

A second pass removed more truly orphaned files:

- `Auralis/DataModels/NFTAnimation.swift`
- `Auralis/DataModels/NFTExamples.swift`
- `Auralis/MusicApp/AI/Audio Engine/Playlist/PlaylistStore.swift`
- `Auralis/NFTMetadataAnalyzer.swift`

This round was more interesting because some “unused” code was only unused by the app, not by the test target. `Password.swift` and `ReceiptResetService.swift` looked dead at first glance, but both still have test coverage hanging off them. That is exactly the kind of trap that turns a cleanup into a stealth regression if you move too fast.

The practical lesson: dead in production code and dead in the repository are not the same thing. Sometimes a file is no longer in the product path but is still part of the test contract. If you want it gone, the right move is to remove or rewrite the tests intentionally, not pretend the dependency is not there.

### Aha! Moment

Misleading filenames are a real tax. `NFTImageView.swift` looked suspicious until inspection showed it still houses live support types like `CachedAsyncImage` and `ImageLoader`. The filename was stale; the code was not. Good cleanup work is less “delete everything dusty” and more “confirm which dust is load-bearing.”

### Pitfall

Do not assume a file named like a feature entry point still contains the feature entry point. This codebase has a few places where a file’s name reflects its past life, not its current contents.

### SwiftUI Integrity Pass

This round was less “one giant bug” and more “a pile of small paper cuts that could absolutely gang up on the UI.” The recurring theme was that several views were doing just a bit too much work at exactly the wrong time: during render, on the main actor, or inside fixed layouts that looked fine until Dynamic Type or a smaller phone showed up and started asking rude but fair questions.

What changed:

- `ReceiptPayloadValueView` stopped building recursive identity signatures for every array element just to create row IDs. We switched to stable enumerated indices for array rendering and replaced the rigid 120-point label rail with a `ViewThatFits` fallback. Translation: the receipts UI now spends less time playing “guess who I am” with nested JSON and more time just showing it.
- `ReceiptDetailFact` got the same treatment. The old fixed-width label column was the UI equivalent of insisting every suitcase must fit the same overhead bin. Now it adapts.
- `NewsFeedListingView` now precomputes filtered results instead of refiltering the full query-backed NFT array every render. It also stopped forcing every card to consume the entire viewport height, which was a little too eager on smaller devices.
- `CachedAsyncImage` and `ImageLoader` were the biggest concurrency win. Network fetch plus image downsampling no longer piggyback on `@MainActor` work triggered from initialization. The view now drives loading with `.task`, while decode/downsample happens off-main. This is one of those fixes that rarely gets applause but absolutely earns fewer hitches.
- `NewPlaylistView` dropped a synchronous `Data(contentsOf:)` read from the Image Playground callback. Blocking the UI thread to load image data is the sort of move that works fine right up until it doesn’t, usually while a user is tapping the screen wondering why the app got philosophical.
- `HomeTabView` now caches its derived receipt previews and music counts into state refreshed on scope changes instead of repeatedly remapping and refiltering the same query data every render.
- A handful of UI ergonomics got tightened up too: `GuestPassCard` now sizes its animated mask relative to the card instead of dragging an 800x800 effect across every device, `EnergyCardView` and `RecentlyPlayedMiniCard` now reuse formatters instead of minting new ones on demand, and the mini/now-playing controls plus newsfeed action rail picked up explicit accessibility labels and better hit targets.

The practical lesson here is that SwiftUI usually behaves well when views stay honest: declare UI, react to state, and keep anything expensive or side-effectful out of the hot path. Once a view starts doing filtering, formatting, network work, file IO, and identity synthesis at render time, it is basically trying to be a stage manager, lighting rig, and lead actor all at once. That show gets messy.

### Privacy and Concurrency Paper Cuts: The Bugs That Look Administrative Until They Ship

This round of cleanup had two different flavors of risk, and both are the kind that love to hide behind “probably fine.”

First, the Swift 6 concurrency audit. Two service wrappers were using `@unchecked Sendable` as a hall pass:

- `AlchemyNFTService` had mutable request-degradation state hanging off an otherwise sendable service wrapper
- `Web3EthereumNameServiceClient` wrapped a third-party ENS client that the compiler could not prove safe to share across async boundaries

The right fix was not to keep arguing with the compiler. `AlchemyNFTService` now keeps its mutable mode behind a tiny internal actor while the public wrapper stays genuinely `Sendable`. The ENS client took a different route: instead of sharing one questionable object forever, it now stores only the RPC URL and builds the `EthereumNameService` on demand per request. Same behavior, much cleaner ownership story. The compiler stopped complaining because the code actually became safer, which is usually a good sign that the compiler is being annoying for the right reason.

Second, the App Store metadata cleanup. This was the paperwork version of “the plane flies great, shame about the missing wings.” The app already used:

- camera capture for playlist artwork
- photo-library selection for playlist artwork flows
- `UserDefaults` and `@AppStorage` across search, pinned items, ENS caching, passwords, and shell state

But the bundle metadata had holes:

- `Info.plist` was missing camera and photo-library purpose strings
- there was no `PrivacyInfo.xcprivacy` manifest at all

That is exactly the kind of issue that waits patiently until the first review submission, then smacks you with a rejection email. The fix was intentionally small and explicit: add the usage descriptions, add a privacy manifest, and declare the required-reason API usage we can substantiate today, which is `UserDefaults` with reason `CA92.1`.

There was one more small but memorable lesson in tooling humility. `Journal.md` and `AGENTS.md` existed on disk the whole time, but the Xcode project tools could not see them because the workspace uses filesystem-synced groups and those root docs sit outside the synced folders. In other words, the files were real, but not real to that particular lens. Good reminder: when a tool says “missing,” always ask “missing where?”

### Regression Cleanup: When "Optimization" Turns Into a Hallucination

Three regressions showed up immediately once the uncommitted changes were reviewed together:

- `MiniPlayerView` wrapped the whole mini player in a `Button` while the transport controls inside it were also buttons. That is the SwiftUI equivalent of putting a big plastic cover over the dashboard and then wondering why the radio knobs feel weird. The outer tap target could interfere with the inner controls, so the fix was to restore the original non-nested tap behavior for opening Now Playing.
- `NewsFeedListingView` cached filtered NFT results in `@State` and only refreshed them when a few coarse triggers changed. Same count, different records? Stale UI. The view had basically started remembering yesterday's groceries because the number of bags looked the same.
- `HomeTabView` did the same trick with derived counts and recent-activity previews. It cached live SwiftData-derived information into local state, which meant the dashboard could quietly drift away from reality if records changed without changing the total count.

The fix in all three cases was a nice reminder that not every repeated computation is a caching opportunity. If a value is cheap enough and directly derived from live source-of-truth data, letting SwiftUI recompute it is often the more correct move. Local state should own user intent or view-local lifecycle, not become a sidecar database because it feels "faster."

### Swift 6 Test Harness Cleanup: The Compiler Became the Grumpiest Reviewer in the Room

A batch of test failures turned out not to be product bugs at all, but Swift 6 concurrency rules finally collecting old debts from the test target.

What broke:

- several test doubles conformed to `Sendable` protocols while still keeping mutable arrays and dictionaries as plain stored properties
- a couple of tests pushed `@MainActor` types like `NFTService`, `NFTFetcher`, and `AppRouter` across nonisolated boundaries
- the URLProtocol-based network mocks used shared static handlers, which is basically a polite way of saying “global mutable state with good intentions”
- parameterized tests had helper case types that were not `Sendable`, which made Swift Testing’s macros unhappy

The cleanup was surgical:

- stub state that needed mutation moved behind actors or tiny synchronized wrappers
- tests that were already dealing with main-actor production types were explicitly marked `@MainActor` instead of pretending they were actor-neutral
- generic `TestCase` helpers were made `Sendable` so Swift Testing could safely package arguments
- the URLProtocol mocks were rewritten to use explicit `nonisolated(unsafe)` handlers with a documented test-only invariant: install, run one request flow, clear immediately

This was a good reminder that test code is still code. A flaky test double is just production chaos in a fake mustache. Swift 6 is forcing the suite to be honest about who owns mutable state and which execution lane a type actually lives on. Annoying in the moment, very useful in the long run.

One small but telling follow-up bug showed up in `ShellStatusPresentationTests`: the suite was calling main-actor presentation helpers from a nonisolated context, then trying to carry a tuple containing `ShellStatusAction` back across that boundary. The compiler quite reasonably objected. The right fix was not to weaken the production API, but to admit what the test was already doing and mark the suite `@MainActor`. That is a very Swift 6 lesson: if the code lives on the main actor, say so plainly and stop pretending it is actor-agnostic.

The same pattern showed up again in `NFTCollectionDetailPresentationTests`, except this time it surfaced as a runtime breakpoint while exercising a perfectly ordinary collection filter. The filter logic was fine. The test was not. `NFTCollectionDetailView.makePresentation(...)` is main-actor isolated because it lives on a SwiftUI view type, and the test tried to call it from a nonisolated synchronous context. Marking the suite `@MainActor` fixed the crash without diluting the production boundary. Same lesson, louder voice.

Another smaller but useful cleanup landed in `NFTImageLoaderTests`. The tests were still assuming `ImageLoader` begins fetching in `init`, but the production loader had already been modernized to start work from `loadIfNeeded()` so SwiftUI can trigger it from `.task`. In other words, the app moved to explicit lifecycle-driven loading, while the tests were still living in the old “constructor does everything” universe. The fix was to update the tests to call `loadIfNeeded()` before asserting on post-load error state. That keeps the tests aligned with the real contract instead of pressuring the production code back toward hidden initializer side effects.

### Release Hygiene and Refresh Churn: The Quiet Bugs That Make an App Feel Expensive

This pass was all about the kind of bugs users rarely describe with precision. They do not say, “your dependency seam is inconsistent” or “your refresh path is issuing too many SwiftData fetches.” They say, “the app felt weird,” which is much more annoying because they are usually right.

Three things changed:

- `AccountSwitcherSheet` stopped freelancing its own `AccountEventRecorder` and now uses the same `ShellServiceHub` factory path as the rest of the shell. Before that, one sheet was quietly bypassing the service boundary like a side door with no badge reader.
- `NFTService` got a performance cleanup in the persistence path. Instead of repeatedly fetching the same persisted NFTs, contracts, and collections for every incoming item, it now snapshots those records once per refresh and reuses them. Same end result, much less “ask the database the same question 400 times and act surprised when the UI looks busy.”
- Old metadata-analysis scaffolding was removed from the shipping target. `NFTMetadataAnalyzer.swift` and `NFTExamples.swift` were not part of the product path, but they were still sitting in the app target like rehearsal props left on stage during opening night. That is especially awkward when the analyzer carries hardcoded wallet lists and emits logging you absolutely do not need in a release build.

There was also a smaller cleanup sweep:

- the commented-out metadata-analysis task was removed from `AuralisApp`
- stale commented blocks were removed from `NowPlayingView`
- an unused `playlistImage` state property and a ticket-style placeholder comment were removed from `NewPlaylistView`

The lesson here is simple: “not currently executed” is not the same as “harmless.” Dead release-path code still increases review surface, privacy risk, and cognitive noise. And performance bugs are often less about one catastrophic algorithm and more about a hundred tiny repeated calls taking turns kneecapping the main actor.

### Main-Actor Surgery Without Knocking Over SwiftData

The follow-up bug here was subtle and annoying: we had “fixed” the NFT refresh path, but most of the expensive metadata interpretation still lived inside an `@MainActor` service. Translation: the app was still doing a decent amount of thinking on the UI lane, just with fewer database laps.

The fix was to separate interpretation from mutation.

- Networking trust and fallback cleanup: this round fixed four small-but-real seams that all sat in the “looks fine until prod traffic or privacy expectations get involved” category. The ENS client now actually respects its `allowsOffchainLookup` flag instead of always taking the offchain path and then pretending the toggle mattered. The NFT inventory client now uses an intentional shared session with explicit request/resource timeouts, which finally makes that path behave like the RPC, token, and image providers instead of freelancing on `URLSession.shared`. Gas pricing also got its memory back: if the cache has an expired estimate and the refresh fails, Auralis now keeps the stale estimate instead of dropping the screen into an avoidable empty failure state. And the ERC-20 provider stopped shredding HTTP context into a generic “something went weird” bucket. Now non-retryable status failures keep their status code and API message long enough for the UI to say something concrete, which is much better than the old “provider did not respond cleanly” shrug.

- `NFTMetadataUpdater` now knows how to build a pure metadata patch as a sendable value.
- `NFTService` snapshots only the raw metadata inputs it needs, computes those patches in a detached task, then comes back to the main actor to apply the results to SwiftData-backed `NFT` objects.
- cleanup failure receipts were also corrected to use the known requested account and chain instead of reverse-engineering scope from whatever stale NFT array happened to be around after a failure.

This is one of those engineering moves that feels a bit like moving a kitchen remodel into the garage so dinner service can keep running. The heavy chopping and prep happen off to the side; the final plating still happens where the real dishes live.

The practical lesson: if a model object is actor-bound, do not try to brute-force it across concurrency boundaries. Extract the pure inputs, do the expensive interpretation elsewhere, then apply the result back at the ownership boundary. That pattern is safer, easier to explain in code review, and much less likely to produce the kind of “it builds, but now persistence is haunted” regression that ruins a Friday.

### Local Package Footing: Start Small, Wire It For Real

This change was intentionally modest, because the dangerous version of “let’s modularize” is when somebody opens a chainsaw before deciding which wall is load-bearing.

- We added a new local Swift package named `AuralisPrimaryModels` at the repo root and wired it into the app target as an actual package dependency, not as a decorative folder that happens to contain Swift.
- The package currently exports `PrimaryStoreCopy`, which is tiny on purpose. It gives the app one real integration point for primary-store UI copy without forcing a rushed migration of the actual SwiftData model graph into a package before the seams are ready.
- The first usage lives in `AuralisApp`, where the local-storage recovery alert now reads from the package instead of another hardcoded app-local string. Small move, real dependency, zero theater.

The lesson is classic renovation logic: when you want a future guest house, first pour one clean concrete pad and make sure the plumbing reaches it. Do not start by trying to relocate the entire kitchen with dinner service still in progress.

### EOAccount Extraction Plan: Stop Pretending a String-Scoped System Is an Object Graph

This planning pass answered a very specific packaging question: can `EOAccount` move into `AuralisPrimaryModels` without dragging half the app behind it? The useful answer was “yes, but only after we make the schema tell the truth.”

- On paper, `EOAccount` and `NFT` still have a direct SwiftData relationship. In practice, the app already behaves mostly like an ID-scoped system. Queries filter on `accountAddressRawValue`, cleanup deletes by scoped predicates, and `trackedNFTCount` is recomputed from fetch counts instead of walking `account.nfts`.
- That is actually good news. It means the first migration step is not a philosophical rewrite. It is mostly removing a relationship that the app has already outgrown.
- We wrote the migration down as a two-phase plan: first decouple `EOAccount` from `NFT` with minimal churn, then move `EOAccount` into the local package once it no longer depends on the NFT graph. That sequence matters because it separates persistence-behavior risk from module-boundary risk.

The memorable lesson is one architecture keeps teaching in different accents: if the running system already trusts stable IDs more than object references, the model layer should stop cosplaying as a tightly coupled object graph. Better to admit the truth in one controlled diff than let the mismatch keep charging interest.

### Small Defects, Real Consequences

This cleanup round was not glamorous, but it was exactly the sort of work that keeps a release from feeling sloppy.

- `HomeTabView.logout()` used to shrug at SwiftData deletion failures with `try?`. That is the software equivalent of dropping the office keys down a storm drain and marking the task complete. Logout now fails explicitly: if local cleanup throws, we log it, show the user an error, and stop instead of pretending state reset succeeded.
- `AppDeepLinkParser` was passing a token-only chain requirement through receipt routes. Nothing exploded, but it was a logic smell: a receipt route was carrying a backpack full of token assumptions it never used. That requirement is now removed for receipts so the parser says what it means.
- two production error logs were printing wallet addresses as public values during chain-selection persistence failures. Not a crash, but definitely not the kind of observability gift you want to hand over in release logs. Those addresses are now hashed in logs instead.

The lesson is that defect resolution is not always about dramatic stack traces. Sometimes it is about refusing to let “quietly wrong” stay quiet: hidden logout failures, misleading parser wiring, or logs that leak more than they should. That is how a codebase gradually stops surprising you in production.

### Shell State Consolidation: Replacing The Four-Way Argument With One Adult In The Room

This was the big shell refactor the codebase had been asking for in increasingly passive-aggressive ways.

Before the change, the active shell scope was split across four values:

- `currentAddress`
- `currentAccount`
- `currentChain`
- `currentChainId`

That setup worked the same way four people carrying one couch up the stairs “works” right up until somebody turns too early and the whole thing wedges in the hallway.

The new setup puts a real foreman on the job:

- `ActiveShellSelection` is the single address-plus-chain scope.
- `ShellState` is the canonical snapshot of shell control-plane state.
- `ShellAction` is the explicit list of state transitions.
- `ShellStore` is the only owner allowed to mutate shell selection.

The nice part is not just fewer properties. It is fewer *arguments*.

- `MainAuraView` no longer runs a web of shell sync observers.
- `MainTabView` no longer “fixes” chain persistence in `onChange`.
- `AccountSwitcherSheet` no longer writes straight into shell bindings like it found the spare keys.
- gateway/auth flows now activate accounts by sending shell intents instead of poking `currentAccount` directly.

The real war story here was not the reducer itself. It was the migration edge cases.

- The first draft accidentally created the new shell files under a duplicated `Auralis/Auralis/...` subtree. Classic refactor tax: the architecture was cleaner while the file paths briefly looked like a hall of mirrors.
- `HomeTabView` still had a couple of old binding assumptions hiding in its query setup and profile card handoff, which is exactly the kind of leftover that makes a build fail even after the “big” work is done.
- The new shell tests also reminded us that tuple arrays are not automatically pleasant to compare in expectations, which is a tiny but very Swift-shaped papercut.

The payoff is worth it. The shell now behaves like a state machine instead of a negotiation between `@State`, `@AppStorage`, and a few optimistic `onChange` callbacks.

One follow-up bug showed up immediately in review, and it was exactly the kind that architecture refactors love to smuggle in under a fake mustache: cold-start deep links could arrive before `ShellStore` existed, hit `MainAuraView`, and get dropped on the floor. The fix was simple and important. `MainAuraView` now queues the parsed deep link or route error until the store is created and the initial restore has run, then replays that startup routing into the store. In other words: if the user shows up with directions before the front desk has finished booting, we now write them down instead of pretending they never walked in.

We also filled in the reducer test gaps the review called out. `ShellStoreTests` now covers same-account no-ops, inactive and last-account removal, chain persistence failure, deep-link routing and deep-link error surfacing, explicit route-error dismissal, fresh/loading foreground no-op refresh cases, and logout state reset. That is not just more green dots. It means the shell store is now tested on the awkward branches, not just the friendly ones.

### The Service Locator Haircut

The next architecture problem was subtler than the old four-way shell argument, but it had the same bad energy: too much of the UI could still reach into `ShellServiceHub` and quietly ask infrastructure for whatever it wanted. `MainAuraView` was booting real services, `MainTabView` was playing factory bingo for receipts, search, token sync, ENS, and music indexing, and child views were inheriting the same pattern like a family recipe nobody actually likes.

- The important realization was that `ShellServiceHub` is only virtuous as long as it stays in the composition room. Once views receive it directly, it stops being dependency injection and starts being a backstage master key.
- The migration plan for `ARCH-001` deliberately avoids replacing one giant bag with five medium-sized bags wearing fake mustaches. The target is small feature-scoped dependency bundles plus explicit use-case protocols where view code actually needs behavior, not infrastructure trivia.
- The first cut is intentionally narrow: move `MainAuraView` and `ShellStore.live(...)` off the hub first, then tighten `MainTabView` and child surfaces. That sequence matters because it breaks the biggest architectural back-edge without forcing the whole shell through a one-PR demolition derby.

The memorable lesson: a service locator can look tidy in code the same way a junk drawer looks tidy when it still closes. The problem shows up later, when every screen knows where the spare batteries, passport, and mortgage paperwork are supposed to be.

## Engineer's Wisdom

- Dead code removal is only “safe” after verifying inbound references and then building the project. Grep without validation is guesswork.
- Large files attract unrelated responsibilities over time. That is how you end up with domain models living next to abandoned UI experiments.
- The cleanest architecture in the world still loses clarity if old view stacks are left behind after a routing refactor.
- A senior-engineer move here is to treat code archaeology as part of product quality, not as a cosmetic chore.
- SwiftUI performance problems often look tiny in code review. A single formatter in a computed property, one `Data(contentsOf:)`, or one array filter in `body` can seem harmless until it sits on a path that re-renders constantly.
- If a control looks tappable, it should usually be a `Button`. Accessibility is much easier when semantics and visuals are aligned instead of retrofitted later.
- But the inverse also matters: if a region contains other controls, making the whole thing a `Button` can create an interaction turf war. One tap target per job keeps the peace.
- Derived data from `@Query` should stay derived unless you have a strong invalidation story. Caching without complete invalidation rules is just a polite form of lying.
- If a shell selection is conceptually one thing, model it as one thing. Address-now-chain-later is how routing bugs grow legs.

## If I Were Starting Over...

I would put stricter boundaries around feature folders and refuse to let exploratory UI land in `DataModels/`. That one choice would have prevented at least one confusing dead-code pocket.

I would also add a lightweight periodic hygiene pass:

- scan for declaration-only view types
- look for files with zero inbound references
- check whether filenames still match their primary exported types

That is the software equivalent of cleaning the garage before you start storing motorcycles in it.

## 2025-02-14 Config Cleanup Pass

A small but worthwhile configuration sweep landed here. The project was telling two stories about iOS support at the same time: the project-level deployment target said `18.0`, while the app and test targets were all set to `26.0`. Xcode follows the target, so the app was effectively iOS 26-only anyway, but the project file looked like a split-brain system. We aligned the project-level default to `26.0` so the build settings stop arguing with each other.

Privacy metadata also got less poetic and more App-Review-proof. The camera usage string now says what the app actually does: scan a wallet address QR code so the user can add or switch accounts. We also removed the `arkit` required-device capability after confirming the active code paths do not use ARKit or RealityKit. That flag was acting like a velvet rope for devices that had no reason to be excluded.

There was also one dead test file hanging around like an abandoned movie set: `AuralisTests.swift` existed on disk, was fully commented out, and was not even part of the Xcode project. It is gone now. Finally, the app target marketing version moved from `00.00.01` to `0.1.0`, which is much less likely to make App Store metadata look like it was typed during a power outage.

## 2025-02-14 SwiftData Optional Safety Pass

One small bug fix here carried more weight than its size suggested. `NFTMetadataUpdater.applyImagePatch(...)` was force-unwrapping `nft.image` immediately after creating it when nil. In ordinary code that looks harmless. In persistence-backed code, especially with optionals hanging off model objects, it is exactly the kind of shortcut that feels fine until the day it becomes the stack trace.

The fix was boring on purpose: materialize the image value if needed, bind it safely, mutate the local value, then assign it back. No behavior change, no architectural drama, just one less “trust me” in a path that runs during metadata refreshes. Good bug fixes often look like this. They remove a sharp edge before anybody gets the chance to bleed on it.

## 2025-02-14 Search History Starts Moving Into SwiftData

This pass begins the search-history migration by adding a dedicated `SearchHistoryRecord` model instead of treating history like a blob of preferences. That old `UserDefaults` approach worked the way a junk drawer works: technically the batteries and paper clips are stored, but good luck managing scope, recency, deduplication, and deletes without eventually muttering at the drawer.

The new model is intentionally small: account scope, normalized query, display query, timestamp, and a scoped ID that says “one row per normalized query per account.” The important decision was to keep nil-account history as actual `nil` in storage rather than inventing another fake string scope. That keeps the persistence model honest and makes the next store refactor much less likely to grow weird translation logic around a made-up sentinel.

## 2025-02-14 Search History Finishes The Move

The rest of the migration landed cleanly, which is always suspicious but occasionally true. `SearchHistoryStore` no longer serializes one giant JSON blob into `UserDefaults`; it now talks directly to SwiftData through `ModelContext`, does scoped upserts, trims each account to its retention window, and deletes rows like a normal piece of persisted app data instead of pretending to be a settings toggle with ambition.

The wiring changed in the right place too. `ShellServiceHub` now builds the store with a model context, `MainTabView` passes that store into `SearchRootView`, and `PrivacyResetService` clears the same SwiftData-backed rows during local privacy resets. That is the important architectural win: one persistence story, one construction path, and one reset seam.

The testing story got better as well. The old tests were proving that `UserDefaults` could remember a JSON blob. The new tests prove the behavior we actually care about: per-account deduplication, nil-account isolation, max-entry trimming, full clears, and privacy reset clearing persisted search history. That is a much better contract. It tests the restaurant, not just whether the pantry door closes.

## 2025-02-14 Search History Error Propagation

One follow-up review caught a bug that looked administrative until you picture it in a privacy reset flow. `SearchHistoryStore` had moved to SwiftData, but its write paths still behaved like a shrug emoji: save failures were logged and then quietly ignored. That meant `recordCommittedQuery`, scoped clears, and even `clearAll()` could fail underneath the floorboards while callers walked away believing the job was done.

That is especially bad for `PrivacyResetService`. A privacy reset that says “all clear” while search history is still sitting on disk is not a small bookkeeping mistake. That is the software version of a hotel telling you the room was emptied while your suitcase is still under the bed.

The fix was to make search-history mutations throw instead of fail soft. `PrivacyResetService` now propagates those failures properly, and `SearchRootView` handles them like a user-facing product surface should: it keeps the current history snapshot visible, logs the problem, and shows an honest banner instead of pretending the write succeeded. The lesson is simple and worth keeping around: reads can degrade gracefully; destructive writes and privacy actions need a real success signal.

## 2025-02-14 Enum Decode Observability

Another pre-ship review produced a classic engineering trap: a long bug list where some items were real, some were already fixed, and some were just wearing a scary hat.

The worthwhile fixes were the boring, sharp-edged ones:

- `GasPriceEstimateViewModel` moved from `ObservableObject` and `@Published` to `@Observable`, and `GasPriceEstimateView` now owns it with `@State`. Same lifecycle, cleaner alignment with the app’s newer observation model.
- `HomePinnedItemsStore` and `SearchHistoryStore` stopped failing silently on `UserDefaults` encode/decode problems. They still fail soft for users, but now leave log breadcrumbs instead of politely eating the evidence.
- `NFTMetadataUpdater` became a caseless `enum`, which is the type-system version of locking the supply closet so nobody “accidentally” turns a static helper namespace into an instance.

Just as important was what did *not* get changed:

- the `symbolColorRenderingMode(.gradient)` report was stale; current SwiftUI docs and Xcode both accept it
- the prompt-cache eviction complaint was stale; both caches are already capped
- the `URLSession.shared` complaint was stale; `ImageLoader` already uses an explicit session with timeouts
- the “no tests” claim was wildly stale; the repo already has a substantial Swift Testing suite, including coverage for several of the exact areas called out

The lesson: a ship checklist is not a shopping spree. Good pre-release work is equal parts fixing defects and refusing to cargo-cult fixes for problems the code no longer has.

One sharp-edged break *was* real: `NFTService` had evolved from a single `lastSuccessfulRefreshAt` value into a scope-aware lookup keyed by account and chain, but one receipt test file was still behaving like the old property existed. That is the sort of bug that feels petty until it blocks the whole test target and turns release confidence into theater.

The repair was deliberately small. The tests now ask the same question the app asks in production: “for this account, on this chain, when did the last successful refresh happen?” Once the test stopped pretending refresh freshness was global, the test target compiled again and the focused release-safety slice went green.

The lesson is worth keeping: freshness and cache timestamps almost always start life as one innocent value and later become scope-dependent. When that happens, tests should be updated to mirror the real lookup contract immediately, or they become fossilized documentation for an API the app no longer has.

## 2025-04-29 AuraPlay Stops Carrying A Fake Wallet Passport

`AuraPlayWallet` had become the software equivalent of a temporary badge that somehow got promoted to middle management. It existed mostly so AuraPlay could say “I have persisted library data for this address on this chain,” but the real account model in the app was already `EOAccount`. That meant we were carrying two identities for one human story: the shell knew the person as an account, while AuraPlay kept inventing a second little wallet record just to remember sync state.

The merge fixed that split personality in three pieces:

- `EOAccount` now carries AuraPlay per-chain sync metadata. Think of it like adding a proper travel history section to the real passport instead of issuing a separate paper stub every time someone changes terminals.
- `AuraPlayMediaItem` is now scoped directly by `accountAddressRawValue + chainRawValue`. The media store no longer needs a parent wallet row standing nearby like a chaperone.
- The dedicated AuraPlay store shrank to what it actually owns: persisted media items. The “was this chain already synced?” signal moved back to the primary account store where it belongs.

The subtle gotcha was store boundaries. The tempting move would have been “just put `EOAccount` inside the AuraPlay store too,” but that is how one source of truth quietly becomes two synchronized liars. The cleaner design was to let the primary store own identity and sync metadata, and let the AuraPlay store own only its media projection.

There was also a migration wrinkle hiding in plain sight: we still needed the old `AuraPlayWallet` type around as a historical schema artifact so `AuraPlaySchemaV2` could migrate to `AuraPlaySchemaV3`. In other words, the old stage prop is gone from the script, but it still has to sit in the backstage closet long enough for the moving crew to recognize it.

The engineering lesson is a good one:

- if a model exists only to smuggle state that already belongs to a stronger domain type, merge it back before it starts attracting relationships
- if a feature store is really a projection cache, keep it narrow and let the primary store own identity
- if a migration needs legacy types to exist for one more release, keep them explicitly as legacy scaffolding instead of pretending they are still first-class design

## 2025-04-29 AuraPlay Phase 1: Building The Stage Before Moving The Band

AuraPlay finally stopped being a hopeful folder name and started behaving like a real module boundary.

- The first win was structural honesty. The Music tab now routes through an AuraPlay swap seam with a dedicated `Core`, `Domain`, `Services`, and `Presentation` layout under `Auralis/MusicApp/AuraPlay/`. That matters because rebuilds go sideways when “temporary” files all squat in `App/` and quietly become architecture.
- The second win was dependency discipline. The AuraPlay root no longer knows just about a library repository and playback controller. It now receives queue, artwork, logging, and bundle-configuration seams too. Think of it like replacing a garage full of extension cords with a real breaker panel: each circuit now has a labeled place to plug in, and tests can swap components without touching the live audio engine.
- The third win was paperwork honesty. We removed a motion privacy string that described a feature the repo does not actually implement, then wrote source-backed tests for the Info.plist and privacy manifest. This is exactly the kind of thing that saves you from an App Review conversation that starts with “why does your app claim to do this?”
- We also added the repo-level contracts that keep future AuraPlay work from backsliding quietly: SwiftLint guardrails for `print()` and global audio-engine access inside the module, plus a GitHub Actions workflow that resolves packages, runs SwiftLint, builds the app, and runs tests.

The useful engineering lesson here is that a feature rebuild needs two kinds of scaffolding. The visible kind is folders, models, and views. The invisible kind is contracts: privacy declarations, lint rules, CI checks, and a short architecture note that tells future engineers which walls are load-bearing. Skip the second kind and the first kind eventually turns into a haunted house.

## 2025-04-29 AuraPlay Docs Stop Pretending To Be A Ticket Graveyard

One last cleanup pass turned the AuraPlay Phase 1 plan from a historical ticket ledger into something future humans can actually use.

- The old plan file had done its job. It explained how to translate a greenfield-style ticket stack into this repo, but once the foundation work landed, the remaining value was no longer “which ticket was P1-006?” It was “what is still incomplete, how do I QA this on a phone, what does good look like, and how does Phase 2 start without stepping on a rake?”
- So the doc set got split into the same kind of retained-artifact pattern already used for Phase 0. Instead of one big markdown sandwich with stale acceptance criteria, AuraPlay now has dedicated docs for future work, physical-device QA, UI/design audit, Phase 2 handoff, and a compact LLM context file.
- This is one of those boring-sounding senior-engineer moves that pays off disproportionally. Good documentation is not just “more writing.” It is reducing the amount of archaeology the next person has to perform before they can make one safe change.

The useful lesson: planning docs and memory docs are not the same species. A planning doc is scaffolding while a feature is being built. A memory doc is the map you keep after the scaffolding comes down.

Another pair of failures turned out to be a nice split-screen of “real product bug” versus “test harness bug.”

On the product side, `ContextService` was correctly returning a resolved snapshot for a losing refresh generation during a race, but it only emitted `context.built` receipts for the winner. That meant one caller got a real result and zero audit breadcrumb, which is exactly the kind of observability gap that makes concurrency bugs feel paranormal. The fix was to log the receipt for every resolved refresh result while still keeping only the winning generation as the persisted live snapshot.

On the testability side, `ImageLoader` had hidden its `URLSession` behind a static singleton. That is convenient right up until you need a deterministic test and discover your mock protocol is yelling through the window while the loader is using a different door. The cleanup was simple and worth keeping: preserve the production default session, but allow a test session to be injected. Once the test could bring its own `URLSessionConfiguration` with `protocolClasses`, the video-content-type rejection case became stable again.

That combo is a good engineering reminder:

- racing work should not silently skip receipts just because it loses the UI-update election
- networking helpers should own sensible defaults, but not trap tests behind hidden globals

Another small-but-real cleanup landed in `EOAccountSource`. The decoder already had a compatibility fallback for unknown raw values, which is good. The bad part was that it failed silently and quietly relabeled anything unfamiliar as `.manualEntry`. That is like a hotel front desk receiving a reservation for a room type it does not recognize and just handing the guest a standard key without telling anyone.

The fix keeps the fallback but adds logging when it happens. That preserves resilience for old or future data while giving us a breadcrumb if the stored schema or imported payloads drift. Compatibility is good. Compatibility with amnesia is not.

## 2025-02-14 SwiftUI Ownership Seam for Gas Previews

`GasPriceEstimateView` had a classic SwiftUI ownership smell: it was correctly using `@StateObject`, but it hardcoded creation of its own view model with no injection seam. That makes the production path easy and the preview or test path awkward, which is how teams end up writing “just ignore the preview” comments and then wondering why nobody trusts the component.

The fix was to keep ownership where it belongs and make initialization more honest. The view still owns a `@StateObject`, but now it can be initialized with a caller-supplied `GasPriceEstimateViewModel` when previews or tests need control. Same lifecycle semantics, better seams, less fake helplessness.

## 2025-02-14 Timer Discipline in the Gas View Model

The music engine had a similar kind of timing bug, just wearing a different costume. `AudioEngine.progress` looked dynamic from the outside, but it was really just a computed value sitting on top of a private clock. SwiftUI only redraws an `ObservableObject` when published state changes, so the mini player and now-playing slider were basically staring at a very accurate watch locked in a drawer.

The fix was to make playback position an actual published signal. `AudioEngine` now keeps `@Published private(set) var currentTime`, updates it immediately during seek/pause/stop/load transitions, and runs a small main-actor display loop while playback is active to push fresh values into the UI every quarter second. Same underlying playback math, but now the views hear about it instead of needing telepathy.

## 2025-02-14 Review Triage: Real Bugs Versus Scary-Sounding Notes

Another review pass produced one of the most common late-stage engineering chores: separate the problems from the vibes. A few notes looked alarming on paper, but only some of them were actually bugs.

The real product bug was in the gas screen. `GasPriceEstimateView` used `estimate == nil && !isLoading` as the path to its error state, while `GasPriceEstimateViewModel.setChain(...)` deliberately waited 300 ms before starting the first fetch. That left a tiny opening where the view had no estimate, was not yet loading, and briefly dressed up as a failure. In user terms, it could flash an error before it had even tried. The fix was to give the view model an explicit `phase` (`initial`, `loading`, `loaded`, `failed`) so the UI can tell the difference between “haven't started yet” and “actually failed.” Same data, much better manners.

The `NFTService` note turned out to be a regression-risk seam, not a production bug. The service intentionally preserves the terminal fetch error across `nftFetcher.reset()`, but the behavior was being enforced by comments and careful ordering rather than a test. That is the software equivalent of a fragile glass sign reading “please do not bump this.” The right fix was not to rewrite the production path; it was to add a regression test proving the fetcher still gets reset while the terminal error survives.

The shell-service note was mostly a false alarm wearing architecture language. `ShellServiceHub.live` does call `ReceiptStores.live(modelContext:)` multiple times, but the store is cached by the long-lived `ModelContext` identity, and the existing boundary tests already prove the factories share the same persistence seam. Good note to verify, not a bug to churn.

The macOS stub in `AuralisApp` was also real, just simpler: the project is configured for `iphoneos`, so the conditional `Settings` / `MenuBarExtra` block was dead furniture. That kind of stub is harmless right up until it starts a confusing conversation during release review. Removing it made the app entry point say exactly what the target actually supports.

The lesson here is a classic SwiftUI one: a computed property is not observation. If the UI needs to animate or track something over time, give it a real source of truth that emits changes on purpose.
The gas estimator had a timer pattern that worked, but a little too optimistically. Every refresh tick launched a fresh task to get back onto the main actor, and while `isLoading` reduced overlap, it was not the same thing as having an actual single-flight contract. That distinction matters in refresh code because “probably not overlapping” is how you eventually end up with a support ticket that begins with “sometimes the spinner feels haunted.”

The cleanup kept the timer but changed the control flow. The tick now bridges back to `@MainActor`, immediately checks tracked task state, and only starts a new fetch when no other fetch task is in flight. In other words, the lobby still has a doorman, but now there is also a guest list.

## 2025-02-14 One Source of Truth Means One Actual Storage Path

`ModeState` had a split personality. It read mode through `@AppStorage`, but it also carried a separate injected `UserDefaults` writer closure. In production, the closure was a no-op and `@AppStorage` did the work. In tests, both wrote, but reads still came from the property wrapper. That is the kind of design that looks dependency-injected from ten feet away and then quietly cheats when you get closer.

The fix was to stop pretending there were two equal storage paths. `ModeState` now initializes `@AppStorage` with the injected defaults store when one is provided, so reads and writes finally agree on where truth lives. The app still force-normalizes Phase 0 to `.observe`; it just does it through one pipe instead of two.

## 2025-02-14 Localization Consistency Pass

Localization bugs rarely arrive dressed like bugs. More often they show up as one error type using `NSLocalizedString`, another using raw literals, and a third doing a little of both like it is trying to keep everyone happy. `TagError` had exactly that problem, and `AccountStoreError` was still entirely raw-string based despite clearly being user-facing.

The fix was not glamorous: normalize them. The copy did not need to become more complicated; it just needed to stop freelancing. Once error formatting moved behind explicit localization keys and format strings, the code started telling one story again. That is a useful lesson in product polish: inconsistency is often what users feel, even when they cannot name it.

## 2025-02-14 Chain Label Cleanup

`routingDisplayName` had been taking a lazy shortcut for less-common networks by capitalizing raw values like `arbnova-mainnet`. That produced UI labels with all the elegance of a shipping manifest. The app already had proper human-readable network names elsewhere; this one path was just skipping the nice front door and sneaking in through the loading dock.

The fix was to derive routing labels from `networkName`, stripping only the redundant `Mainnet` and `Testnet` suffixes, while preserving the intentionally short flagship names like `Ethereum` and `Base`. A focused test now covers representative networks so labels do not quietly slide back into hyphen soup later.

## 2025-02-14 Newsfeed Action Honesty

The newsfeed had a classic first-impression bug: a shiny action rail full of buttons that looked ready for social energy, then delivered absolutely nothing. Like, comment, share, and bookmark were all visible in `NewsFeedCardButtons`, all accessibility-labeled, and all wired to empty closures. There was even a fake creator-profile button sitting at the top like a cardboard elevator panel.

The right fix was not to invent pretend behavior. The action rail now keeps only the menu path that actually works today, and the decorative avatar placeholder is no longer advertised as an interactive control. This is a useful product lesson disguised as a UI cleanup: if an affordance is not real yet, do not let it cosplay as shipped functionality.

## 2025-02-14 Search History Persistence Decision

This one is less about a crashing bug and more about putting the right furniture in the right room. `SearchHistoryStore` was living in `UserDefaults`, which is fine when you are saving things like “show captions by default” or “last selected segment.” It is much less convincing when the data starts behaving like a tiny database.

Search history in Auralis is:

- scoped to an account
- ordered by recency
- deduplicated by normalized query
- trimmed by per-account retention rules
- cleared by privacy reset flows

That is not a casual preference. That is persisted app data wearing a `UserDefaults` nametag and hoping nobody asks follow-up questions.

The migration plan is to move search history into SwiftData without making `SearchRootView` pay the price for the persistence correction. The key move is to keep the existing `SearchHistoryStore` API and keep `SearchHistoryEntry` as the UI-facing value type, while swapping the storage engine underneath it. In other words, the front-of-house search UI keeps taking orders the same way, while the kitchen quietly upgrades from a notepad to an actual ticket rail.

There is one deliberate bit of caution here: the initial migration should preserve the current `"global"` no-account sentinel exactly as-is and support a one-time legacy import from the old `UserDefaults` blob. That keeps the first shipping change mechanical and boring, which is exactly what you want from a persistence migration. Exciting migrations are usually just bugs with better marketing.

## 2025-02-14 Rate Limits, Privacy Resets, and Other Ways Software Can Accidentally Lie

This pass was a good example of three different bugs sharing one personality flaw: the app was sometimes technically doing *something*, but not always the thing it claimed to be doing.

First, the NFT rate-limit path. `AlchemyNFTService` already parsed `Retry-After`, which looked reassuring until you followed the baton handoff and discovered `NFTFetcher` promptly ignored it and ran its own exponential backoff anyway. That is like a traffic cop telling you “wait 30 seconds” and the driver responding “I have my own counting system.” The fetcher now honors provider-supplied retry delays when they exist, then falls back to local backoff only when the server gives no guidance. Small change, real production consequence: fewer self-inflicted retries during a rate-limit window.

Second, the privacy reset story stopped leaving fingerprints behind. `PrivacyResetService` already cleared a respectable pile of local state, but it still left the active wallet selection and wallet-scoped pinned home actions sitting in `UserDefaults`. That is not a privacy reset; that is a privacy reset with a forwarding address. The reset path now clears those wallet-linked remnants too, and the settings copy says so plainly instead of overselling the wipe.

Third, the gas screen learned the difference between “cached but still useful” and “cached because the live provider is broken.” The old path would happily fall back to stale gas data after almost any refresh failure, including auth and configuration failures, then present a polite cached state as if nothing especially actionable had happened. That is yesterday's weather report with today's timestamp pasted on top. The provider now only reuses stale cache for genuinely transient failures, keeps unauthorized/configuration failures loud, and maps gas errors into the same kind of user-facing language the other provider surfaces already use.

There was one more cleanup hiding in the wings: a couple of SwiftData writes were still running directly on the main actor in UI code. `AccountSwitcherSheet` chain changes and playlist create/delete flows now push persistence through model actors instead of doing paperwork in front of the customer. The useful pattern here is simple and worth repeating: let SwiftUI own intent and feedback, let model actors own mutation, and do not ask the UI lane to be your file clerk just because the write is “probably small.”

## 2025-02-14 Foreground Refresh Discipline

This pass fixed a shell-level behavior problem that users rarely report in precise terms but absolutely feel. Before the change, the app had no explicit foreground lifecycle policy, so coming back from the background did not give the shell a real chance to ask the important question: “is my active NFT scope still fresh enough to trust?”

The new rule is simple and opinionated:

- foreground resume checks the active account scope against `NFTService.refreshTTL`
- if the data is still fresh, do nothing
- if it is stale, refresh the active scope
- if a refresh is already in flight, leave it alone

That keeps the app from behaving like an overcaffeinated intern who re-fetches everything every time the user glances away for two seconds.

There was a second UX cleanup folded into the same change. The full-screen loading experience now belongs to first-entry bootstrap only. Once the user has already reached the authenticated shell at least once, later refreshes stay in the main UI and surface through shared loading/freshness state instead of kicking the user back to a giant blocking loading screen. Same work, much less drama.

One more subtle but important adjustment: shell refresh work is no longer explicitly cancelled just because the root view disappears during app lifecycle transitions. That does not guarantee iOS will always let background work finish forever, because the OS is still the OS, but it does stop the app from sabotaging its own in-flight refresh the moment the scene changes state. Sometimes stability work is exactly that boring: remove the line of code that keeps pulling the fire alarm.

## 2025-02-14 Refresh Identity And Receipt Scope Fixes

This pass was a good reminder that persistence bugs rarely arrive alone. They travel in a pack, usually wearing different hats and pretending to be unrelated.

The first problem was local NFT tags getting erased during refresh. The network refresh pipeline was rebuilding NFTs from provider data and then merging them back into SwiftData, but tags are not provider data at all. They are local annotations. In practice, that meant a refresh could behave like an overenthusiastic housekeeper who sees sticky notes on your desk and throws them out because they were not part of the original furniture set. The fix was to stop treating tags as refresh-owned state and preserve the existing persisted tags during merge.

The second problem was sneakier. Metadata parsing was allowed to overwrite `tokenId`, but the scoped NFT `id` had already been computed earlier in the refresh flow. That created the software equivalent of changing the label on a filing cabinet drawer without updating the index card in the front office. Dedupe, upsert, and stale-cleanup all depend on stable identity, so the right fix was to reapply refresh scope after metadata mutation so `tokenId`, contract scope, account scope, chain scope, and `id` all tell the same story again.

Receipts had their own identity crisis. Some receipt producers hashed wallet addresses inside the sanitized payload, which is the right privacy move for export-safe payloads, but the timeline model was also trying to recover account scope from that same sanitized payload later. That is like shredding the mailing label for privacy and then asking the mailroom to sort by street address. We split those concerns apart. Receipts now store explicit account and chain timeline metadata separately from the sanitized payload, and the receipts timeline no longer filters by chain implicitly. That matches the actual product rule better: if you are looking at receipts for an account, you should see the account's receipts across chains unless you explicitly choose otherwise.

The last fix was about audit-trail honesty. `AccountStore.createWatchAccount(... overwriteExisting: true)` could log a removal receipt before the underlying save had actually succeeded. That is a dangerous pattern because receipts are supposed to describe facts, not hopes. The fix was to delay overwrite-path receipt emission until after persistence commits successfully, while preserving the existing logical ordering of `removed` followed by `added` for successful replacements.

## 2025-02-14 Scope Freshness And Context Churn Cleanup

This round was all about teaching the shell to stop smearing one scope's state all over another scope's dashboard.

The first bug was a classic “single variable, many realities” problem. `NFTService` kept one `lastSuccessfulRefreshAt` timestamp for the entire app, even though refreshes are scoped by account and chain. That meant refreshing Account A on Base could make Account B on Ethereum look fresh too. The foreground refresh policy would then politely decline to refresh the actually stale scope because some other scope had recently done its homework. The fix was to store freshness by `(account, chain)` scope and make every consumer ask for the active scope explicitly. No more communal toothbrush.

The second problem lived in the chrome/context layer. `MainTabView` was using one refresh trigger for both real remote refresh work and tiny local preference changes like pinning home actions. Because `ContextService.refresh()` always resolved native balance from the provider, a harmless local UI change could quietly cause a network read and a fresh `context.built` receipt. That is the engineering equivalent of ordering a sticky note and getting a forklift. The fix split the path in two: remote-worthy changes still run the full refresh pipeline, while local-only changes rebuild the context snapshot using the cached balance for the same scope.

There was one more audit-trail honesty fix hiding inside that context work. `ContextService` could finish building a snapshot, lose the generation race, and still emit a `context.built` receipt for a snapshot the UI never actually adopted. We tightened that contract so only the winning generation, the one that really becomes active state, gets to write the receipt. If a snapshot loses the race, it loses the receipt too. Receipts should describe what happened, not what nearly happened in a parallel universe.

Finally, we removed a stray `currentCursor` write from the NFT refresh path. It was being persisted to `UserDefaults`, but nothing in the app read it back, scoped it, or reset it intentionally. That made it less of a cache and more of a ghost note left in the attic. Better to delete the fake contract than pretend there is a pagination-resume feature when there is not.

## 2025-02-14 Search History Plan Reset

One planning document had wandered into an alternate timeline where the app had already shipped, users had legacy `UserDefaults` search history in the wild, and we needed a careful migration dance. That would have been a respectable problem if it were real. It is not.

Search history has not shipped yet, so there is nothing to migrate and nobody to rescue from an old storage format. The right move is much simpler: stop writing design fiction and implement the first real version directly on SwiftData. That means no dual-read store, no import pass, no “remove fallback next release” cleanup chore waiting like a booby trap in the backlog.

The useful lesson here is that architecture should match the product timeline, not some generic best-practices screenplay. Migration code is a tax you pay only when history exists. Before launch, it is just extra moving parts pretending to be prudence.

## 2025-02-14 Empty Legacy Folder Cleanup

This was a small cleanup with a useful moral. The repo still talked about `MusicApp/OLD/` like it was a haunted wing of the house: excluded from SwiftLint, mentioned in docs, and treated as something engineers should tiptoe around. The problem was that there was no haunted wing. The folder was empty, not in the project, and not shipping anything.

So the cleanup was straightforward: remove the stale SwiftLint exclusion, delete the empty directory, and stop telling future engineers spooky stories about legacy music code that is not actually there. This is one of those hygiene tasks that pays off by making the repo tell the truth faster.

## 2025-02-14 Explicit Bad-Data Provider Coverage

This one was a testing honesty fix. We already had product-level behavior for unreadable provider payloads: the app classifies decode failures as invalid-response conditions and shows sane fallback copy. The weak spot was lower down. The provider suite did not have a focused case proving that a `200 OK` response with malformed JSON body actually fails at the decode boundary.

That distinction matters. A lot of networking suites are good at testing angry servers and bad at testing lying servers. But a `200` with nonsense in the body is exactly the kind of bug that slips through if you only cover status codes and downstream presentation mapping. It is the API equivalent of a waiter smiling, saying “everything is ready,” and then serving a plate with the ingredients still in the grocery bag.

The fix was small and deliberate:

- `AlchemyNFTService` now accepts an injected `URLSession` while keeping `.shared` as the production default
- `ProviderAbstractionTests` now sends a malformed success payload through the real provider path and asserts that `DecodingError` is surfaced explicitly

The useful lesson: “bad data coverage” is not the same as “some later layer eventually noticed something was wrong.” If the provider contract says “decode this success body,” the tests should prove that malformed success bodies fail exactly there.

## 2025-02-14 Provider Error Honesty And Cache Cleanup

This pass was the software equivalent of replacing a building's emergency signage after discovering half the arrows pointed to “somewhere over there.”

The first issue was error translation. The NFT presentation layer knew how to talk about `NFTFetcher.FetcherError`, but typed provider failures from `ProviderAbstractionError` and `AlchemyNFTService.APIError` were slipping through the cracks and getting flattened into generic “unavailable” messaging. Native-balance and ERC-20 flows had a similar problem: raw `URLError`s could bubble up far enough that the UI stopped being specific and started sounding diplomatic. The fix was to tighten the translation contract. Offline is now a first-class provider state, NFT failures understand provider abstraction and Alchemy API errors directly, and the balance/token surfaces now distinguish offline from ordinary provider unavailability.

The second issue was provider resilience. The NFT envelope insisted on fields like `totalCount` and `validAt`, and the token providers decoded entire arrays in one gulp. That meant one malformed row could take the whole page down with it, which is dramatic behavior for what should have been a recoverable bad-record problem. We switched those paths to lossy array decoding and made the envelope metadata optional where the app already treats it as advisory. In plain English: keep the good crates when one tomato in the shipment arrives cursed.

Then there was retry timing. Several network clients only understood numeric `Retry-After` headers and ignored the equally valid HTTP-date form. A shared parser now handles both styles across NFT, token, gas, and audio download code so server-directed backoff is not interpreted like a half-heard train announcement.

ENS caching also got a long-overdue cleanup. When a name's address changed, the resolver correctly detected `mappingChanged` but left the stale forward cache entry behind like an old mailing label on a suitcase. That meant repeated lookups could keep tripping over yesterday's truth. The resolver now removes the stale entry before surfacing the change, and corrupt ENS cache blobs are discarded on load instead of quietly haunting future launches.

Finally, the keychain password store stopped doing high-wire updates with no net. It used to delete the old secret before attempting `SecItemAdd`, so a failed add could turn “update password” into “erase password and act surprised.” The save path now uses the normal add-or-update flow without pre-deleting the existing item.

## 2025-02-14 Haptics Main-Actor Boundary Fix

This was a classic UIKit-meets-Swift-6 paper cut. `AuraHaptics` looked like a tiny harmless wrapper around `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`, but UIKit now treats those generators as main-actor isolated. So the code was effectively trying to ring the front-desk bell from outside the lobby and the compiler quite reasonably objected.

The fix was intentionally narrow: mark only `impact(_:)` and `notification(_:)` as `@MainActor` instead of slapping main-actor isolation across the whole wrapper. That keeps the stored `isEnabled` flag lightweight while making the actual UIKit touchpoints obey the real threading contract.

The lesson is simple and worth remembering: when a wrapper exists mostly to hide framework details, it still inherits the framework's isolation rules. A tiny facade does not magically make UIKit non-UI.

## 2025-02-14 Release Secrets And Mode-State Concurrency Hardening

This pass was about two different kinds of honesty: not leaking internal config trivia into release builds, and not pretending Swift 6's actor rules are optional just because an old workaround compiles.

- `SettingsView` had a debug-friendly provider status panel that reported whether the Alchemy key was configured. Useful during development, terrible release behavior. Shipping that is like leaving the restaurant's pantry checklist taped to the front door. The whole section now lives behind `#if DEBUG`, including the trust label, explanatory copy, and status rows.
- `ModeState` also got aligned with the rest of the shell's actor model. It owns `@AppStorage` and `@Published` state that the UI reads on the main actor, so leaving the class nonisolated was effectively asking Swift 6 to stop noticing a race because the code “usually” behaves. The class is now `@MainActor`, and the receipt helper that reads `mode` is explicitly main-actor isolated too.
- The sneakiest bug was the environment fallback. `ModeStateKey.defaultValue` had been using `nonisolated(unsafe)`, which is concurrency for “trust me, I brought a blindfold.” The replacement keeps the protocol requirement nonisolated, but backs it with a main-actor-owned singleton accessed through `MainActor.assumeIsolated`. Same minimal blast radius, much more truthful safety story.
- We also checked the password-store escape hatch. `PasswordStores.test(...)` had no production call sites, so the fix there was prevention: make the plaintext `UserDefaults` store debug-only and say plainly in code that it is test-only.

The useful lesson: pre-ship hardening is often less about adding features and more about removing quiet lies. A release build should not narrate its secret wiring, and concurrency annotations should describe the real ownership model instead of suppressing the compiler until launch day.

## 2025-02-14 Signing Failure From A Ghost Capability

This one was not a Swift bug at all. The project was failing before compilation really mattered because the target still advertised `com.apple.developer.carplay-audio` in `Auralis.entitlements`, and the current signing setup could not provision that capability.

That kind of issue is sneaky because it looks like “the app does not build,” but the real problem is more like showing up at airport security with paperwork for a trip you are not actually taking. Xcode tries to provision the entitlement, cannot find a valid profile path for it, and the whole build stops at the gate.

The fix was deliberately small:

- remove the unsupported CarPlay audio entitlement from `Auralis.entitlements`
- rebuild immediately to confirm the failure was contractual, not source-level

After that, the project built cleanly again.

The lesson: entitlements are part of the product contract, not harmless metadata. If the app is not actively using a capability, leaving the key around is just inviting signing trouble later.

## 2025-02-14 AuraPlay Logging Privacy Fix

This one was a small diff with a very real blast radius. `AuraPlayEntryView` was logging library refreshes with the active wallet address interpolated directly into the message. That is the sort of thing that feels harmless during development and then becomes embarrassing the moment a production log export exists.

The fix stayed narrow on purpose:

- keep the refresh log, because “did the library refresh path run?” is still useful operationally
- remove the raw account address from the message
- replace it with coarse state only: either there is an active account or there is not

In plain English, we kept the breadcrumb and stopped leaving the user's house key next to it.

The lesson: privacy bugs are often not giant crypto failures. Sometimes they are just a well-meaning debug sentence that knows too much.

## AuraPlay Phase 2 Ship-Baseline Reality Check

This pass was less about adding a flashy new subsystem and more about forcing the repo to stop underselling and overselling itself at the same time.

- The undersell was in the live AuraPlay root. The code already had a real Phase 2 persistence spine: SwiftData container, schema, wallet/token/media models, sync service, and a repository that can prefer persisted AuraPlay media over the legacy indexer. But the UI and migration enum were still calling the active path “Phase 1 foundation,” which is like installing a new basement and then leaving a sign on the door that says “temporary plywood only.” We renamed the active stage and updated the copy so the app describes the architecture it actually has.
- The oversell risk was more subtle. The plan talked about search, playlists, playback history, and deterministic integration scenarios in the same breath as the persistence spine, which makes it easy for a future reader to mentally mark all of Phase 2 as “basically there.” That is how later-phase work becomes accidental scope debt. We made the plan say the quiet part out loud: Waves 1 and 2 are the current ship baseline, and Waves 3 and 4 are explicitly deferred.
- We also added a regression test for the migration seam that really matters right now: once a scoped wallet has been mirrored into AuraPlay storage, the library repository must prefer the persisted media graph instead of pretending the legacy indexer is still the source of truth. That is the difference between a migration ramp and a decorative diagram.

The lesson: ship readiness is not just “does the code compile?” Sometimes it is “does the product, the plan, and the tests all tell the same story, or are they each living in a different timeline?”

## AuraPlay Privacy Reset: The Basement Counts Too

This one was a straight-up truth-in-advertising bug. The Settings screen promised that “Clear Local Privacy Data” would wipe local support data, but AuraPlay Phase 2 had quietly moved part of the music inventory into its own SwiftData store under Application Support. So the reset flow was cleaning the kitchen and leaving the basement shelves untouched.

- The root cause was architectural, not visual. `PrivacyResetService` already knew how to clear the main app container, caches, receipts, search history, and token holdings. But AuraPlay persistence had become a second storage boundary, and deletion responsibility never followed it there.
- The fix was to stop pretending that one reset seam still owned all the data. We added an explicit `AuraPlayPersistenceResetting` contract, wired the live reset path through a store-file cleanup service, and taught the privacy reset flow to clear the AuraPlay store alongside the original app data.
- The regression test does the important boring work: create the AuraPlay store artifacts, run the reset, and prove the store file plus SQLite sidecars are actually gone. That is much better than a test that only checks whether somebody remembered to call a method with a reassuring name.

The lesson: whenever you split persistence, you also split the cleanup contract. If you add a new basement and forget to hand the janitor a key, the basement becomes privacy debt.

## AuraPlay Container Lifetime: Stop Reopening The Record Vault

This one was a quieter bug than a failed reset, but it had the same architectural smell: the ownership boundary was in the wrong room. `AuraPlayTabRootView` was creating its own `ModelContainer` inside the view initializer, which sounds harmless until you remember SwiftUI treats view values like stage props, not heirlooms.

- The problem was lifecycle mismatch. `MainTabView.body` can rebuild normally as state changes, and the Music tab subtree can be recreated without meaning “please reopen the AuraPlay store from scratch.” But the container creation lived inside that subtree, so the app was repeatedly reopening the same persistence store and recreating fresh `@ModelActor` services around it.
- The fix was to move AuraPlay container ownership up to `MainAuraView`, where the shell already owns other long-lived services like the shared audio engine and NFT orchestration. The Music path now receives one stable `ModelContainer` instance through `MainTabView` and into `AuraPlayTabRootView` instead of manufacturing a new vault key every time SwiftUI redraws the hallway.
- This is one of those bugs that rarely screams during happy-path demos and still matters before ship. Multiple live containers pointed at the same store are the persistence equivalent of having three bartenders separately convinced they are the only one tracking the tab.

The lesson: in SwiftUI, expensive stateful resources belong to the owner with the longest honest lifetime, not the nearest convenient initializer.

## AuraPlay Store Boot Failure: Degrade The Feature, Not The Process

This was the kind of crash that makes engineers wince because it was technically tidy and operationally reckless. AuraPlay’s store boot used `fatalError` on container creation failure. That is fine for a prototype, less fine for a shipped Music tab behind a normal user tap.

- The failure mode got worse once Phase 2 persistence became the default Music path. A corrupted store file or file-system hiccup no longer meant “AuraPlay is unavailable”; it meant “the app dies when the user opens Music.” That is a bad trade unless the tab is running a nuclear reactor.
- The fix was to make boot failure an availability state instead of an execution state. `MainAuraView` now captures AuraPlay store boot as optional container plus a user-facing fallback message, and `AuraPlayMigrationStage` explicitly resolves back to `.legacy` whenever the Phase 2 store is unavailable.
- The important design choice was containment. We did not create a second recovery architecture or scatter error handling across every AuraPlay dependency. We kept the fallback at the seam where the module gets selected in the first place, which is the right room to decide whether the new record vault is open or whether the app should send users through the old entrance.

The lesson: when a feature-specific store fails to boot, the product should lose the feature slice, not the whole app session.

## AuraPlay Sync Hitch: Let The Front Desk Fetch, Let The Back Room Sort

This one was not a correctness bug so much as a choreography bug. The Phase 2 library sync path was doing more work on `@MainActor` than the UI could politely hide: fetch the wallet-scoped music NFTs, deduplicate them, normalize strings and URLs, sort them, and build the upsert payloads, all while the Music tab was waiting at the door.

- The subtlety here is SwiftData ownership. The source `ModelContext` still belongs to the main actor in this slice, so pretending the whole sync could just “move to background” would be the kind of concurrency fix that writes its own future incident report.
- The real fix was to split the job at the correct seam. The main actor now does the actor-owned fetch and immediately snapshots the relevant NFT fields into `Sendable` value types. Then a detached phase does the heavier in-memory work: deduplication, sorting, string cleanup, artwork URL selection, and request construction.
- We also pulled that detached shaping work into a dedicated request builder instead of leaving a pile of type-level helpers hanging off the sync service. That keeps the service in conductor mode and moves the pure transformation logic into its own instrument case.
- In restaurant terms, the host still checks the reservation book at the front desk because that book lives there. But the host no longer chops vegetables, plates the entrée, and polishes glasses while the line forms at the door.

The lesson: with Swift concurrency, “move it off the main actor” is only a good fix when you first separate actor-owned state access from pure value transformation.

## SwiftData Hardening Pass: Stop Treating The Database Like A Suggestion

This pass was a classic case of the schema saying one thing while parts of the app were quietly behaving like the schema was just inspirational poster text.

- The first bug was account ownership. `EOAccount` claimed it owned `NFT` rows with a cascade relationship, but the refresh pipeline was really just stuffing account addresses into raw string fields and hoping future cleanup code stayed disciplined forever. That is not ownership; that is a sticky note. The fix was to wire a real `NFT.account` relationship and assign it during persistence, so deleting an account now has an actual graph to work with instead of a folklore contract.
- The second bug was playlist durability. Playlists were pointing straight at live wallet `NFT` rows, and refresh cleanup was allowed to delete those rows when they disappeared from the latest inventory. That makes a playlist feel less like a saved crate of records and more like a memo saying “these songs existed once.” The fix was to keep playlist membership as a real SwiftData relationship, archive stale playlist-linked NFTs out of active account scope instead of deleting them, and clear playlists explicitly during privacy reset so destructive cleanup removes the whole shelf instead of leaving empty album sleeves behind.
- The receipt timeline had a smaller but very real honesty problem. Receipt counts were scoped by wallet address but not chain, which meant a multi-chain wallet could look busier than the selected timeline actually was. The fix was simple: filter by both address and chain at the store boundary, not after the fact in our heads.
- Receipt fetches also got a practicality lesson. Asking SwiftData for “latest 20” and then reading the whole table before taking a prefix is like asking a bartender for one lime and making them inventory the entire fruit fridge first. The store now uses bounded fetch descriptors for sequence allocation and limited reads.
- The search and home surfaces got a similar cleanup. `SearchRootView` no longer watches the entire NFT and holdings universe when it only cares about the active account and chain, `HomeTabView` now queries only the scoped receipts it actually shows, and the account switcher pushes account ordering down into SwiftData instead of fetching first and sorting in the view like it is grading papers by hand.
- Another hardening pass exposed a privacy-retention leak wearing a perfectly respectable data model costume. Removing or overwriting an account used to clear the `EOAccount` row and its scoped `NFT`s, but it quietly left wallet-scoped token holdings and search history behind like receipts still sitting in yesterday’s coat pocket. The fix was to centralize account-scoped cleanup, delete those support rows alongside the account, and reuse one `SwiftDataNFTCleanup` helper so destructive paths also prune orphaned `NFT.Contract` and `NFT.Collection` records instead of letting the store collect abandoned filing cabinets.
- The music path got its own lane-discipline upgrade too. The expensive AuraPlay sync and music-library rebuild work was still doing too much store-backed thinking on the main actor. That is the software version of making the maître d' run back to the freezer to recount inventory every time a guest asks for a table. The fix was to move the snapshot and rebuild paths behind model actors, keep the UI-facing seams lightweight, and let the main actor go back to being a host instead of an accidental warehouse clerk.

The useful lesson: SwiftData is happiest when relationships are real, query scope is explicit, and cleanup logic works with the graph instead of around it. If the app keeps reaching for raw string scope and whole-table fetches out of habit, the database will still compile and still quietly charge interest later.

## Destructive Cleanup Honesty Pass: Either Commit Or Put The Chairs Back

This bug was a sneaky one because the scary part was not just the delete itself, it was the lie after the delete. `HomeTabView` was running logout cleanup inline, deleting multiple SwiftData buckets, then trying one `save()`. If that save failed, the app told the user “Nothing was changed,” even though the live `ModelContext` could still be sitting there with pending deletions like a restaurant after closing time: chairs on tables, floor half-mopped, cash drawer open, and someone insisting the room was untouched.

- The fix started with a small rule that now has teeth: destructive SwiftData mutations must either commit or explicitly `rollback()`. We added a shared `ModelContext.performRollbackSafeMutation` helper and pushed the logout delete sequence behind `LogoutCleanupService` instead of letting the view orchestrate the teardown itself.
- Privacy reset needed a slightly more nuanced contract. That flow mixes transactional SwiftData deletions with irreversible side effects like cache clearing and AuraPlay persistence cleanup. So we split it into two phases: first the transactional SwiftData reset that can roll back cleanly, then the follow-on cache/store cleanup that may only be able to report partial completion honestly.
- Account removal got pulled into the same discipline. The account store already owned the mutation boundary, but now overwrite/remove paths also use the rollback-safe helper so a failed destructive save does not leave the live context in a half-deleted ghost state.

The lesson: destructive flows need truthfulness as much as they need deletion logic. “Nothing changed” is only acceptable if the code can actually prove it put every chair back where it found it.

## Undo Support Reality Check: A Steering Wheel Needs A Rack

This one was a classic “the dashboard said we had a feature” problem. The app had an `UndoManager` attached to the primary SwiftData context, and destructive UI existed for playlists, account removal, and logout. That sounds like undo support right up until you read Apple’s contract: SwiftData only wires automatic undo when the scene or view uses `.modelContainer(..., isUndoEnabled: true)`. In other words, we had a steering wheel bolted to the dashboard, but not actually connected to the rack.

- The first fix was structural. We pulled the primary schema into one shared `PrimaryStoreSchema` definition and changed `AuralisApp` to install the container through SwiftUI’s `modelContainer(..., isUndoEnabled: true)` scene modifier. The app still keeps its “persistent store failed, fall back to in-memory” honesty, but now the normal production path is using the actual SwiftData undo seam instead of a hand-waved approximation.
- The second fix was transactional. Playlist deletes now run inside an explicit undoable mutation with a named action, so the user-facing destructive path maps to one coherent undo unit instead of a pile of side effects that happen to share a timestamp.
- Account removal had a subtler trap: it was deleting through a model-actor context, and Apple’s undo support only tracks saves on the main context. So we moved the destructive account-removal path onto the main context for that action, kept rollback protection, and let SwiftData finally record the deletion in a place the undo manager can see.
- We also added a full-schema in-memory test container for integrity checks. That let us write the tests that actually matter here: playlist delete can be undone, account removal can be undone, and rollback-safe delete helpers really do put the records back when a mutation blows up mid-flight.

The lesson: “has an undo manager” and “supports undo” are not synonyms. On Apple platforms, undo is plumbing. If the pipe is connected to the wrong context, the faucet is decorative.

## Destructive Flow Completion Pass: Stop Leaving Side Doors Unlatched

The first hardening pass fixed the obvious shell-level demolition jobs, but it left a few side doors unlocked: playlist deletion still rode through a convenience extension, AuraPlay reset still did multi-step deletes without rollback wrapping, and a handful of lower-level stores were still using the old “delete a bunch of rows and hope `save()` lands” pattern.

- We closed the playlist gap by introducing an explicit `PlaylistDeletionService` for the user-facing delete path. That means the swipe-to-delete UI now goes through a named destructive boundary instead of calling a model-context helper directly and pretending that was architecture.
- We also finished the plumbing underneath. Token holdings clear-all, search-history clear/remove, receipt reset, and live AuraPlay persistence reset now all use the same rollback-safe mutation helper. The point is not ceremony; the point is that a failed destructive save should leave the room in the same shape it found it.
- The actor-side playlist deletion helper was tightened too. It still exists for non-UI callers, but it now uses transactional rollback semantics instead of raw `delete + save`.
- The practical test story improved as well. The undo coverage now exercises the playlist deletion service and the account-removal undo path against a full primary-store schema container, while the existing privacy/reset tests continue checking rollback-versus-partial-completion behavior.

The lesson: consistency matters more than hero fixes. A codebase is not “safe” because the biggest wrecking ball got guard rails if the smaller wrecking balls are still parked on a slope.

## ARCH-001, First Cut: Take The Master Key Away From The Lobby

This was the first real implementation slice of the `ShellServiceHub` cleanup, and the most important decision was restraint. The goal was not “delete the hub everywhere in one dramatic swing.” The goal was “break the worst dependency direction first without turning the shell into a rubble pile.”

- `MainAuraView` stopped carrying the raw service locator and now takes `ShellBootstrapDependencies` instead. That means the shell entry point still knows how to bootstrap the app, but it no longer casually exposes the whole boiler room to the rest of the UI.
- `ShellStore.live(...)` also lost its `ShellServiceHub` dependency. It now takes a `ShellStoreDependencies` bundle with the exact collaborators it uses: selection persistence, account mutation, refresh coordination, deep-link replay, router effects, receipt logging, and the clock. That is a much more honest reducer boundary.
- `GatewayView`, `MainTabView`, `HomeTabView`, `ProfileDetailView`, and `SettingsView` were trimmed down to the narrower closures or feature bundles they actually consume. In practice, this meant passing things like `accountStoreFactory`, `privacyResetServiceFactory`, or `policyActionHandlerFactory` directly instead of letting views rummage through a global bag of unrelated parts.

The fun bug in this pass was predictable in hindsight: `HomeTabView` still had one secret tunnel back to the old world through logout cleanup. This is exactly how service locator migrations try to cheat. You remove the obvious bag from the initializer, and one last side-effect path is still quietly asking the bag for a wrench in the basement. The fix was to thread `logoutCleanupServiceFactory` through the home feature explicitly and close that side door too.

The last cleanup step was the one that actually makes the ADR feel finished instead of merely “less embarrassing.” `ShellServiceHub` is now private to `AppServices.swift`, and the old boundary tests were replaced with builder-focused tests for shell bootstrap, gateway wiring, main-tab feature wiring, policy gates, and privacy reset. That matters because an architecture migration is not complete when the UI stops touching the old type. It is complete when the old type also stops being a public idea the rest of the codebase can casually re-adopt next Tuesday.

The lesson is delightfully unromantic: architecture migrations get safer the moment you stop trying to be impressive. One well-placed cut at the composition boundary beats a heroic “we replaced DI across the whole app in one diff” story every time.

## ARCH-001 Test Hardening: Audit The Plumbing, Not The Paint

Once the first DI migration cut landed, the obvious next question was whether the test story had actually caught up or whether we had just traded one architectural smell for a very confident shrug. The existing builder tests proved that some live seams still connected to the right stores, but they did not really interrogate the shell state machine itself. That is like checking that the restaurant has a pantry, a stove, and a fridge, while never confirming whether the kitchen staff can still get dinner onto the table in the right order.

- The fix was to add a dedicated `ShellStoreTests` suite that stays completely out of SwiftUI. No view snapshots, no navigation rendering, no “the tab looked roughly fine in Preview.” Just the shell reducer, its collaborators, and the behaviors this migration was supposed to protect.
- The new tests cover the moments where DI architecture either earns its keep or gets exposed as decorative paperwork: restoring persisted selection, repairing bad persisted chain scope from the account record, switching accounts with route resets, persisting chain changes, replaying deep links only when the shell is ready, refreshing stale selections on foreground, and clearing everything cleanly on logout.
- The important engineering choice was fake design. Each collaborator got its own tiny test double with one job: remember what it was asked to do. That keeps the tests readable and avoids the usual service-locator trap where the test setup quietly recreates the same giant bag of mystery wires that production just got rid of.
- There was also a nice little concurrency reminder hiding in the refresh path. `ShellStore` starts refresh work in tasks, so the test suite had to assert the reducer effects after yielding just enough for queued work to settle. Not because we enjoy making async tests harder than they need to be, but because state machines that spawn work need tests that understand when the dominoes are synchronous and when they are politely scheduled for one beat later.

The lesson: when a refactor claims to improve dependency boundaries, the best tests are not the ones that admire the new initializer signatures. The best tests are the ones that force the state machine to drive through every sharp turn and prove the new seams still hold the car together.

## ARCH-002 Boundary Call: Keep Persistence Translation In The Persistence Room

This was one of those architecture questions that sounds small until you realize it decides which type quietly starts collecting everyone else’s chores.

- The question was whether `PrepareNFTMetadataUseCase` should go one step further and manufacture persistence snapshots, or whether `PersistNFTInventoryUseCase` should own that translation. We chose the second option on purpose.
- The clean seam is now explicit: fetch provider inventory, prepare canonical domain inventory, then persist with persistence-owned translation. That means metadata prep gets to stay a domain-shaping step instead of gradually turning into a secret SwiftData adapter wearing a friendlier name.
- This matters because snapshots are not neutral packaging. They usually encode merge keys, local-state carry-forward rules, stale-cleanup inputs, write ordering, and other storage-specific invariants. Once that logic leaks upstream, the “prepare” layer stops being reusable and starts dragging persistence policy around like glitter on a sweater.
- We also locked the pragmatic naming decision for the first PR: keep the shell-facing type named `NFTService`. First earn the architectural separation, then decide later whether the honest final public name should become `NFTRefreshCoordinator`.

The lesson is classic boundary hygiene: if a value mostly exists to help storage make promises, let the storage-side use case own it. Otherwise the domain layer becomes a polite-smelling basement full of persistence boxes.

## Legacy Music Deletion Recon: The "Old Music App" Is Smaller Than It Was, But Wider Than It Looks

This pass was documentation work, but the useful part was not the markdown. The useful part was forcing the repo to answer a very specific question honestly: what exactly is still "old music" if the goal is to delete everything that is not AuraPlay?

- The first answer was pleasantly boring. There is no `MusicApp/OLD/` wing left to bulldoze. That ghost was already exorcised.
- The second answer was the real one. The legacy surface is still very alive under `MusicApp/AI/V1/`, but it also leaks into the shipping app through shell routes, the bottom mini player, the full-screen now-playing view, the legacy fallback stage in `AuraPlayTabRootView`, and a handful of shared AI-era types that AuraPlay still imports as bridge infrastructure.
- The most important gotcha was playback ownership. `AudioEngine` may feel like generic plumbing now, but in this repo it still lives under the old AI music path and AuraPlay still talks to it through adapter seams. Deleting the old music app cleanly therefore means either re-homing that engine into AuraPlay or replacing it, not just pretending folder names are architecture.
- The sneakiest dependency was `Playlist`. It looks like old library UI furniture, but the current audio engine still uses `Playlist(name: "Previous")` and `Playlist(name: "Next")` as in-memory queue containers. That is the kind of dependency that turns "simple cleanup" into "why did playback explode?" if nobody writes it down first.
- The old library bridge has the same problem in a different costume. `MusicLibraryIndex.swift` still defines `MusicLibraryItem` and the `MusicLibraryIndexing` seam, and AuraPlay still falls back to that layer when its own persisted graph is not the authority yet. So removing the legacy music experience for real also means deleting the fallback mindset, not just the visible old screens.

The new runbook lives at `Auralis/Auralis/docs/plans/AuraPlay/AuraPlay-Legacy-Music-Removal-Runbook.md`, and its main lesson is simple: repo archaeology beats confidence. Old product surfaces rarely die in one folder. They die in routes, schemas, adapters, cleanup code, tests, and the one "temporary" bridge everyone forgot was still load-bearing.

One important decision got clarified immediately after that audit: `AudioEngine` is not being grandfathered in as a blessed survivor. The plan is to empty `MusicApp/AI/Audio Engine/` out and move detail routing plus the mini-player path fully into AuraPlay. That is the right kind of ruthlessness. Otherwise you do not really delete the old music app; you just give it a fake mustache and let it keep living in the crawlspace.

## AP-SYS-005 Planning Pass: Music Receipts Stop Being Background Noise

This planning pass was a useful reminder that “receipt” and “log line” are cousins, not twins. Logs are what the app mutters to itself in the back room. Receipts are what it should be willing to say out loud later when Mission Control asks, “what exactly happened here?”

- The first important discovery was that the receipt plumbing is already real and reusable. `StoredReceipt`, `SwiftDataReceiptStore`, `ReceiptEventLogger`, and the timeline/detail views already give us the filing cabinet. Music does not need a second cabinet with “special audio papers” scribbled on the front.
- The second discovery was that the active music code is split like a house with a new kitchen and an old furnace. `AuraPlay/` is the current product-facing shell, but `AI/Audio Engine/` still owns the concrete playback and playlist mutation seams. That means playlist receipts belong down in the mutation layer, not in some shiny SwiftUI button that only happens to call it today.
- The third lesson was about honesty under pressure. `AudioEngine` already has cancellation and auto-advance logic, which means playback receipts can lie very easily if they fire too early. A cancelled load is not “playback started.” A superseded track is not “playback completed.” The plan locks that down before implementation gets clever.
- There was also a surprisingly practical architecture choice around actors. The ticket asks for `user`, `system`, `operator`, and `plugin`, but the app’s top-level receipt actor model is still just `user` or `system`. Instead of widening global types for one ticket, the better move is the same trick used in external-link receipts: keep the coarse top-level actor, then use payload and provenance to tell the sharper story.

The memorable bit: music receipts are not there to make the app sound busy. They are there so the app can testify later without improvising.

## AP-SYS-005 Status Pass: The Repo Already Built Half The Bridge

This was a good old-fashioned documentation reality check. The plan file was still talking like the band had not shown up yet, while the repo was already halfway through soundcheck.

- The first useful discovery was that the “future architecture” from the planning doc is no longer future. `MusicReceiptEventType`, `MusicReceiptPayloads`, `MusicReceiptEventLogger`, and even a dry-run auto-organization service already exist. In other words, the blueprint was still warning us to pour the foundation while the studs and wiring were already in the walls.
- The second discovery was more important than the first: implemented is not the same thing as shipped. Playlist receipts are wired into the real persistence seam. Policy-block receipts are wired into the existing gate. Playback and queue receipts are wired into `AudioEngine`. But the auto-organization dry run still looks like a well-built stage prop unless a real product path actually calls it.
- The third lesson was about verification humility. The app builds cleanly, which is worth something. But the targeted music receipt tests came back from the Xcode runner as `No result`, which is the testing equivalent of a witness shrugging and saying, “I was definitely at the scene, but I did not actually see anything.” That means the status doc had to say “incomplete verification” plainly instead of playing lawyer with the wording.
- The sneaky architecture lesson is that stale planning docs are not harmless. Once a strategy file claims types are missing when they already exist, it stops being guidance and starts being a trap. The next engineer can waste time building a second bridge right next to the first one just because the map forgot to update.

The sticky takeaway: codebases age like cities, not spreadsheets. If you want the truth, do not just read the zoning document. Walk the streets and see which buildings are already standing.

## SEC-006 Follow-Through: Confirmation Is The Lock, Logging Is The Clipboard

This security pass had a subtle contract question hiding inside a reasonable-sounding review comment: if receipt logging fails, should the confirmed Safari handoff fail too?

- We kept the hard boundary in the right place. The meaningful security gate is the second user action, not the receipt write. If the user explicitly reviews the destination and taps `Open in Safari`, the app should honor that choice even if the audit trail has a bad day.
- The implementation now says that plainly in code instead of mumbling it through `try?`. `ExternalLinkOpenFlow` still attempts receipt logging first, but logging is best-effort and the confirmed handoff proceeds either way.
- The testing strategy also got more honest. We are not pretending to have UI coverage we did not write. Instead, the unit suites now do more of the useful heavy lifting: policy coverage expands across every supported explorer host plus the approved IPFS gateways and Arweave host, and the flow tests now pin the “logging failure does not block a confirmed open” rule directly.

The lesson is a good one to keep around: security boundaries and observability boundaries are not the same thing. The lock on the door is the explicit confirmation step. The clipboard is the receipt log. Important? Yes. The same thing? Absolutely not.

## SEC-006 Cleanup Pass: Reusable Means Not Smuggling Newsfeed Types Into App-Level Helpers

The first SEC-006 pass got the behavior right, but it left a small architectural banana peel on the floor. `ExternalLinkPolicy` was supposed to be app-level and reusable, yet it still accepted `NFTExternalDestination`, a tiny type declared inside `OpenSeaLink.swift`. That is the software equivalent of building a good city water main and then routing it through one specific coffee shop’s basement.

- The fix was intentionally boring: promote the candidate URL model into the helper layer as `ExternalLinkCandidateDestination`, then point the NFT-detail buttons and policy tests at that shared type.
- The important part is not the rename. The important part is that future artwork, audio, IPFS, Arweave, or settings-link call sites can now use the confirmation policy without importing a Newsfeed component just to carry a `label` and a `url`.
- This is one of those senior-engineer cleanup moves that does not change the demo, but it changes whether the next feature arrives as a clean extension or as a “why does Settings depend on NFT detail?” incident report.

The sticky lesson: reusable abstractions are not reusable if their input types are hiding in a product leaf node wearing fake glasses.

## AccountsCore Migration: Move The Wallet Clerk Out Of The Lobby

This migration moved the account lifecycle clerk into its own room. `AccountsCore` now owns the reusable account store, validation results, account mutation result types, account events, the recorder protocol, and the no-op recorder. `EOAccount` stayed exactly where the ticket said it should stay: in `AuralisPrimaryModels`, because it is still part of the shared persisted model vocabulary rather than a service object.

- The important boundary call was receipt ownership. The generic account event contract moved into `AccountsCore`, but `ReceiptBackedAccountEventRecorder` stayed app-side as the adapter to the current receipt infrastructure. That keeps the package useful without making it swallow the whole receipts subsystem on day one.
- The migration used real imports instead of compatibility typealiases. App and test call sites now import `AccountsCore` where they use `AccountStore`, `AccountEvent`, or account mutation result types.
- A small audit-log lesson popped out during validation: account removal should not erase the account receipt history it just helped create. The package-side account cleanup now removes account-scoped cache and inventory data while preserving receipts as the audit trail.
- The shell tests also caught a refresh timing smell. `ShellStore` used to schedule a separate task just to send `.refreshStarted`, which let tests observe the shell in the awkward half-second before refresh work was actually visible. Refresh state now starts synchronously, and only the actual refresh operation runs in the task.

The sticky lesson: package extraction is not only moving files. It is deciding which promises belong at the reusable boundary and which adapters should stay close to the app plumbing.

## AgentIdentityCore Migration: ENS Gets Its Own Passport Office

The ENS stack moved out of the general networking pile and into `AgentIdentityCore`, which is a better home for identity resolution than a folder full of provider machinery. ENS is not just “another HTTP call”; it is identity evidence. A name, an address, a stale cache hit, and a forward-verified reverse lookup all carry trust meaning, so they deserve a boundary with a name that says what they are doing.

- `AgentIdentityCore` now owns the ENS contracts, cache state/store, reset service, provider client protocol, unavailable client, Web3-backed client, resolver, provenance, and error types.
- The app kept `ReceiptBackedENSEventRecorder` as a bridge. That is the right split: the package can report identity events without knowing how Auralis stores receipts.
- `ENSResolvers` was split into reusable package composition plus an app extension in `AppENSResolvers.swift`. The package takes a tiny ENS provider configuration contract; the app adapts its existing Alchemy/provider configuration and receipt store into that contract.
- Validation found a SwiftData cleanup trap while running nearby privacy tests. Bulk deletes were not clearing pending inserted fixture rows for several model shapes, so logout cleanup now fetches and deletes NFTs, music library items, and receipts explicitly. Boring, but much less magical.

The memorable rule: identity resolution should not live in the same junk drawer as generic provider plumbing. Put the passport office where everyone can find it, and keep the receipt printer plugged into the app.

## ReceiptsCore Migration: The Ledger Moves Into Its Own Vault

Receipts finally got the low-level package boundary they had been quietly asking for. `ReceiptsCore` now owns the append-only store contract, raw payload field vocabulary, sanitizer, SwiftData-backed store, reset service, and generic logger. The stored receipt model itself stayed in `AuralisPrimaryModels`, which keeps the persistence vocabulary shared without making the app target the owner of every receipt behavior.

- The important split was `ReceiptEventLogger`. The package owns the generic `append(...)` behavior: sanitize, draft, store, log failures. The app keeps feature-specific conveniences like app launch, context build, external-link open, copy action, and music library indexing in `AppReceiptEventLogging.swift`.
- That boundary keeps `ReceiptsCore` low in the graph. It does not need to know about `ContextSnapshot`, `ExternalLinkOpenProvenance`, shell state, or music indexing just to provide the ledger.
- The SwiftData reset path now uses explicit fetch/delete for receipts, matching the cleanup lesson from the privacy reset validation instead of relying on bulk delete behavior in places where pending inserted rows can surprise the tests.
- Account receipt adapters, ENS receipt adapters, external-link flow logging, and shell dependency builders all stayed green after moving the ledger underneath them.

The sticky lesson: a receipt package should be a vault, not a scrapbook. It stores and sanitizes facts. Product stories can write into it, but they should not live inside it.

## PolicyCore Migration: The Rulebook Leaves The UI Drawer

The policy gate finally moved out of `ModeState.swift`, which had been trying to be three things at once: the app's persisted mode switch, SwiftUI environment plumbing, and the bouncer deciding which actions are allowed through the door. That worked while Observe mode was tiny, but it was the wrong shape for code that other packages and tests need to trust.

- `PolicyCore` now owns the reusable rulebook: `AppMode`, `PolicyControlledAction`, `PolicyGateResult`, `ActionPolicyGate`, `PolicyActionGating`, and `PolicyActionGateService`.
- The app kept `ModeState`, `EnvironmentValues.modeState`, `View.modeState(_:)`, and `ModeReceiptAugmentor`, because those are SwiftUI/AppStorage concerns rather than reusable policy logic.
- Generic denial receipt writing moved with the core gate through `ReceiptsCore`, while music-specific policy receipts stayed app-side in `AppActionPolicyGate.swift`. That keeps the package honest: it can log a policy denial without learning what a music export is.
- Validation covered the important contract: the app builds, blocked Observe actions still write `policy.denied`, plugin actions still pass, music policy blocks still write their music receipt, and shell dependency wiring still resolves the policy gate through shared receipts.

The sticky lesson: policy code is a rulebook, not a settings screen. Keep the bouncer near the door, but do not make it also own the wallpaper.

## CapabilitiesCore Migration: Stop Passing Around Handwritten Name Tags

Capabilities used to show up as raw strings in receipts and policy paths. That is fine when there are three of them and everyone remembers the spelling. It gets fragile once music, policy, approvals, and future operator flows all need to agree that `music_export` means the same thing everywhere.

- `CapabilitiesCore` now owns the canonical capability vocabulary: `CapabilityID`, `CapabilityCategory`, `CapabilityDescriptor`, `CapabilityUseContext`, `CapabilityDecision`, and registry/mapping helpers.
- `PolicyCore` now maps each `PolicyControlledAction` to a canonical `CapabilityID`, so policy decisions have a bridge into the same capability language the rest of the system can use.
- Music receipts now pass `CapabilityID` values through `MusicReceiptEventLogger` and `MusicPolicyReceiptContext`, while preserving the exact existing raw values in stored receipt payloads.
- Validation kept the migration focused: the app builds, policy gate tests pass, and the changed music capability paths pass. One broader playlist receipt test still exposes the existing sanitizer behavior for nested playlist titles, so that was left untouched instead of being smuggled into this package migration.

The sticky lesson: strings are fine for display, but bad as passports. Once multiple systems need to recognize a capability, give it an ID card and make everyone check the same one.

## OperatorCore Migration: The Door Guard Moves Out Of The View

External links look like simple buttons, but they are really handoffs to the outside world. That makes them operator territory: validate the destination, preserve who initiated the handoff, write the receipt if possible, and then open the URL only after confirmation.

- `OperatorCore` now owns the external-link domain contracts: candidate and confirmation destinations, validation failures, allowlist policy, provenance, open requests, the event logging protocol, and the open flow.
- SwiftUI stayed in the app. `ExternalLinkConfirmationSheet` and `OpenSeaLink` import the package, but the package does not know how the confirmation UI is presented.
- The app kept a small `AppExternalLinkEventLogger` adapter around `ReceiptEventLogger`, avoiding a retroactive conformance between two imported modules.
- Validation covered the useful surface area: the app builds, supported hosts still pass, blocked hosts and unsafe schemes still fail, confirmed opens still log before opening, logging failure still does not block the confirmed handoff, and operator/plugin provenance remains preserved in receipts.

The sticky lesson: opening a browser is not just navigation when a system, operator, or plugin can initiate it. Treat it like a controlled handoff, not a random tap target.

## NFTKit Migration: The Inventory Warehouse Gets Its Own Loading Dock

`NFTKit` is now the home for the NFT and token-inventory service layer: Alchemy NFT fetching, token balance fetching, refresh orchestration, metadata preparation, SwiftData persistence/cleanup, provider failures, and `TokenHoldingsStore`. The shared model nouns (`NFT`, `TokenHolding`, `Chain`) still live in `AuralisPrimaryModels`, which keeps the package from pretending it owns the whole data dictionary.

- The app and tests now import `NFTKit` at the call sites that use those services directly. That replaces the old “keep the app target as a typealias hallway” style of migration with real module ownership.
- A practical boundary wrinkle showed up immediately: provider configuration, retry parsing, decimal formatting, and `Secrets` are not glamorous NFT features, but the moved providers depend on them. They moved with the package so the warehouse has its own loading dock instead of borrowing the app’s side door.
- One Xcode-specific gotcha remains: the local `NFTKit` package product must be added to the app target through Xcode’s package UI. Editing the project file by hand while Xcode is open is a good way to turn a clean migration into project-file confetti.

The sticky lesson: a package boundary is not just a folder move. If callers still see the old module, you have only rearranged shelves. Real extraction means importing the new warehouse by name.

## Provider Package Planning: Draw The Plumbing Before Moving The Pipes

The next modularization question is about provider and adapter packages: `ProviderKit`, `ChainProviders`, `ENS`, `ExplorerAdapter`, plus focused storage packages. The useful answer is not “move every network-looking file into one shiny package.” That would just turn the app target’s junk drawer into a package-shaped junk drawer.

- `ProviderKit` should own API keys, endpoint configuration, retry/backoff, RPC/HTTP transport, and Alchemy clients. It is the utility room for provider plumbing.
- `ChainProviders` should own chain capability policy and provider composition. It decides what a chain can do; it should not perform the network calls itself.
- `ENS` should own resolver protocols, the Web3 client, cache store, cache entries, errors, provenance, and provider-backed ENS configuration. ENS is a complete domain, not a permanent corner of `AgentIdentityCore` and not mere adapter glue.
- Storage splits into five focused packages: `ReceiptStorage`, `AccountStorage`, `TokenStorage`, `SwiftDataAdapters`, and `UserDefaultsAdapters`. That keeps domain-specific stores from hiding inside a generic storage junk drawer, while shared SwiftData and UserDefaults mechanics still get a reusable home.
- `ExplorerAdapter` should build typed explorer and marketplace destinations. It should not open URLs or present confirmation UI.

The sticky lesson: package names are promises. `ProviderKit` should not become “everything involving the internet,” and `SwiftDataAdapters` should not become “every type that once touched SwiftData.” Good boundaries are boring enough that the dependency graph can explain them without a meeting.

The lesson: a good ticket should make the next engineer dangerous in the useful way. If they still have to guess package names, file moves, dependency direction, and acceptance tests, it is not an implementation ticket yet. It is just architecture wallpaper.

## ProviderKit / ChainProviders Checkpoint: The Pipes Moved, The Fuse Box Did Not

The provider split got its next real checkpoint. `ProviderKit` now owns the concrete Alchemy RPC and gas-pricing providers, plus the provider-facing native balance and gas estimate contracts they need to compile outside the app. `ChainProviders` now owns the safe generic composition factory for gas pricing and native balance providers, while NFT/token inventory construction stays in the app-side factory to avoid dragging `NFTKit` into the chain policy package.

- `AlchemyRPCProvider`, `AlchemyGasPricingProvider`, `NativeBalance`, `NativeBalanceProviding`, `GasPricingProviding`, `GasPriceEstimate`, and `GasPriceCache` moved under `ProviderKit`.
- `ProviderKit` deliberately does not import `ChainProviders`. It has a tiny internal EVM support check because provider transport is lower in the graph; `ChainProviders` can depend on `ProviderKit`, but not the other way around.
- `ReadOnlyChainProviderFactory` now lives in `ChainProviders` for gas/native balance composition. The app's `ReadOnlyProviderFactory` delegates those two paths there and keeps NFT/token paths locally.
- ENS extraction hit an Xcode project boundary: a new `ENS` package cannot be imported by `AgentIdentityCore` or the app until the package product is added to the Xcode project dependency graph. Because the project file is off-limits, the safe move was to restore the build and leave ENS for a checkpoint that is allowed to update project metadata.

The sticky lesson: moving pipes is easy until the fuse box says it has never heard of the new room. Package extraction is source code plus project wiring; pretending the wiring is optional just creates a build that cannot find its modules.

## AccountStorage Migration: The Key Rack Gets Its Own Closet

Account persistence finally stopped living inside `AccountsCore`. That package now owns the account vocabulary and contracts: validation results, store errors, account activation/removal results, account event recording, and the `AccountStoring` protocol. The SwiftData machinery moved into `AccountStorage` as `SwiftDataAccountStore`.

- The important boundary is simple: feature code that only needs “an account store” imports `AccountsCore` and receives `any AccountStoring`; composition code that actually builds the SwiftData store imports `AccountStorage`.
- We kept `AccountStore` in `AccountsCore` as a pure validation namespace, not as a typealias backdoor. Pasted/scanned address validation is still available to UI without dragging SwiftData storage into those views.
- The concrete store kept the existing behavior: canonical address normalization, duplicate handling, overwrite semantics, sorted account listing, undo-aware removal, account-scoped cleanup, and receipt/event logging.
- `AccountStorageTests` now owns the SwiftData storage contract with in-memory containers: save, lookup, overwrite-without-duplicates, delete/fallback, ordering, and invalid address handling.

The sticky lesson: contracts are the key rack; persistence is the locked closet behind it. Most of the app should ask for a key by name, not know which shelf the locksmith uses.

## ReceiptStorage Migration: The Vault Door Moves, The Ledger Stays Honest

Receipts got the same package-boundary treatment as accounts. `ReceiptsCore` now keeps the durable receipt language: drafts, records, payload sanitizing, the store/reset protocols, and `ReceiptEventLogger`. The SwiftData-backed storage machinery moved into `ReceiptStorage`, where it belongs.

- `SwiftDataReceiptStore`, `ReceiptPersistenceStore`, `ReceiptStores.live(modelContext:)`, and `SwiftDataReceiptResetService` now live in `ReceiptStorage`.
- The generic `ReceiptResetService` stayed in `ReceiptsCore` because it only talks to the `ReceiptStore` protocol. The concrete live reset factory moved with SwiftData.
- App composition and feature adapters that build a local store now import `ReceiptStorage`; code that only logs or accepts a receipt store still imports `ReceiptsCore`.
- `ReceiptStorageTests` covers the storage contract with in-memory SwiftData: append, timeline ordering, export ordering, destructive reset, inserted-unsaved reset cleanup, and sanitizer-through-logger behavior.

The useful lesson: receipt logging is not the same thing as receipt storage. The logger writes the story, the sanitizer redacts the sensitive bits, and the storage package owns the vault where the story lands.

## SwiftDataAdapters: Shared Tools, Not A Storage Junk Drawer

The storage strategy is now more than a document. `SwiftDataAdapters` stopped being a placeholder and took ownership of the shared SwiftData mutation mechanics that both `AccountStorage` and `ReceiptStorage` were carrying around locally.

- The shared package now exposes rollback-safe and undoable `ModelContext` mutation helpers.
- `AccountStorage` uses those helpers for account creation, overwrite cleanup, and undo-aware account removal.
- `ReceiptStorage` uses the same helpers for append/reset safety, including the reset path that cleans up inserted-but-unsaved receipts.
- The app still keeps domain stores out of `SwiftDataAdapters`, which is the whole point. A helper package should be a toolbox, not a moving truck for every model that has ever touched SwiftData.

The sticky lesson: shared infrastructure earns its place when two real packages use it. Anything broader than that is how a tidy toolbox turns into the drawer where old batteries and mystery screws go to retire.

## TokenStorage Migration: Portfolio Shelves Leave The NFT Warehouse

Token holdings are no longer stored by `NFTKit`. `NFTKit` still owns the provider-facing token contracts for now, but the concrete SwiftData persistence adapter moved into `TokenStorage` as `SwiftDataTokenHoldingsStore`.

- This uses the ticket's option A: `TokenStorage` depends on `NFTKit` for `ProviderTokenHolding` and token freshness helpers. No `TokenCore` package was invented during this pass.
- App composition and ERC-20 UI construction now import `TokenStorage` directly when they build the concrete store.
- The old `TokenHoldingsStore` name was retired instead of preserved through a typealias. The new name says what the type actually is: a SwiftData-backed token holdings adapter.
- `TokenStorageTests` covers native and ERC-20 writes, account/chain scoping, stale replacement within a single scope, metadata placeholder fields, clear-all reset, and invalid account scope errors.

The practical gotcha: source code can move faster than Xcode's package graph. The local package still has to be attached to the app target through Xcode before `import TokenStorage` can build there. Once that wiring is in, this is a real package boundary rather than another module-shaped hallway.

## UserDefaultsAdapters: The Tiny Pantry Gets Its Own Label

Not every storage package needs to be a database vault. Some app state is just a small jar on the pantry shelf: pinned home actions, shell selection, little Codable blobs that belong in `UserDefaults` as long as they are handled consistently.

- `UserDefaultsAdapters` now owns the boring-but-important Codable array mechanics: load, save, clear, and explicit corrupt-payload policy.
- `HomePinnedItemsStore` still owns all home-specific behavior: account scoping, launcher actions, max pinned count, and UI-facing decisions. The package only knows how to store records.
- `UserDefaultsShellSelectionPersistence` became the second real consumer. It uses the helper for the new storage shape while still reading and writing the legacy `currentAccountAddress` and `currentChainId` keys so existing installs do not forget who was checked in at the front desk.
- We deliberately used real imports instead of typealias bridges. A moved storage adapter should be an honest module boundary, not a cardboard cutout standing where the old type used to be.

The lesson: shared helpers should be small enough to explain in one breath and useful enough to have two customers. Otherwise you are not extracting infrastructure; you are just moving clutter into a new closet.

## ENS Migration: The Name Service Gets Its Own Desk

ENS used to live inside `AgentIdentityCore`, which made the package name do too much work. Agent identity and Ethereum name resolution are related, but they are not the same job. That is like asking the concierge to also run DNS for the whole hotel.

- `ENS` is now the home for resolver protocols, cache records, resolution provenance/errors, Web3 client code, cache reset support, and the ProviderKit-backed ENS configuration adapter.
- App code that actually speaks ENS now imports `ENS` directly. `AgentIdentityCore` no longer re-exports or owns the ENS implementation.
- The receipt-backed ENS event recorder stayed in the app because it knows Auralis receipt taxonomy. The package owns name resolution; the app owns how product events are narrated.
- Resolver behavior tests moved into `ENSTests`, where they can exercise cache, stale fallback, mapping-change, reverse-lookup, and provider-configuration behavior without pretending they are app tests.

The useful lesson: a package boundary should tell the truth about the domain. ENS is not a side pocket of agent identity; it is its own service desk with its own cache, provider configuration, and failure language.

## ChainProviders Completion: The Support Matrix Gets A Clipboard

`ChainProviders` crossed the line from “package-shaped idea” to actual policy owner. The app no longer needs an app-local networking extension to ask whether a chain supports EVM RPC or ERC-20 holdings; that decision now lives in the chain/provider package where future provider composition work can find it.

- The public `Chain` capability checks now enumerate every supported chain explicitly instead of leaning on `default`.
- The tests keep their own expected chain list, so adding a new `Chain` case forces a real capability decision.
- The app-side `ReadOnlyProviderFactory` delegates gas and native-balance construction to `ReadOnlyChainProviderFactory`, while NFT/token inventory construction stays app-side to avoid a dependency cycle with `NFTKit`.
- `ProviderKit` still keeps a tiny internal EVM guard because the dependency direction matters: `ChainProviders` can build on `ProviderKit`, but transport should not reach back upward into policy.

The sticky lesson: a support matrix is not a vibe check. It is a clipboard with every chain named on it, and new chains do not get to sneak through the side door as “probably EVM.”

## ExplorerAdapter Migration: The Map Drawer Gets Labels

Explorer URLs stopped being little bits of string glue scattered near buttons. `ExplorerAdapter` is now the map drawer: given a typed destination and a chain, it either hands back a precise URL or refuses with a typed error.

- `ExplorerCatalog` owns chain-to-explorer labels and base URLs for every current EVM chain in `Chain`.
- `ExplorerURLBuilder` builds address, transaction, token, and NFT URLs without falling back to Ethereum mainnet when a chain is unsupported.
- `OpenSeaDestinationBuilder` owns marketplace asset URLs and keeps OpenSea support deliberately narrower than generic explorer support.
- `OperatorCore` still owns external-link validation and confirmation policy; its host allowlist now matches the explorer catalog hosts the app can generate.

The useful lesson: outbound links are product trust surfaces, not decoration. A wrong explorer URL is like giving someone the right street address in the wrong city, so the package now makes every supported chain say exactly where its map lives.

## ProviderKit Checkpoint: Move the Plumbing, Leave the Menu Copy Upstairs

The ProviderKit migration had already done the big furniture move: configuration, secrets, retry parsing, request throttling, native balance, gas pricing, and the live Alchemy RPC/gas clients now live in the package that owns provider plumbing. This pass tightened the checkpoint instead of pretending every provider-adjacent word belongs there.

- The important boundary call was leaving `NFTProviderFailure` in `NFTKit`. It sounds shared from the name, but the implementation still speaks fluent NFT: `NFTFetcher.FetcherError`, `AlchemyNFTService.APIError`, and collection-refresh presentation copy. Moving that into `ProviderKit` would have been like storing the restaurant menu in the boiler room just because both mention soup.
- ProviderKit’s package tests cover the pieces the package truly owns, and the active `AuralisTests` provider suite mirrors the ship-critical coverage Xcode can run under the app scheme: missing RPC configuration becoming `missingAPIKey`, invalid endpoint configuration flowing as `invalidURL`, numeric and HTTP-date `Retry-After`, RPC error handling, and native balance behavior.
- The Gas tab stopped building an Alchemy client in feature code. `MainTabDependencies` now receives a gas-pricing provider from the shell composition layer, then injects it into `GasPriceEstimateViewModel`. Same UI, cleaner ownership.
- At this checkpoint, the NFT and token holdings HTTP clients were deliberately still in `NFTKit` for the next transport-split pass. They already used ProviderKit configuration and retry vocabulary, but their orchestration was still tangled enough that pretending this checkpoint finished that split would have been dishonest.

The lesson: package extraction is not a scavenger hunt where every similarly named type gets swept into the new crate. Good boundaries move the plumbing to the plumbing package and leave product language with the product feature that actually uses it.

## ProviderKit Transport Split: The Last Provider Pipes Left NFTKit

The follow-up migration finished the ProviderKit split without turning it into architecture karaoke. The goal was not to invent shiny new client objects just because a planning doc once suggested names. The goal was simpler and better: move the provider transport that already existed to the package that owns provider transport.

- `AlchemyNFTService`, `AlchemyNFTResponse`, `NFTInventoryProviding`, `AlchemyTokenHoldingsProvider`, token balance DTOs, token holdings DTOs, and the lossy array decoder now live in `ProviderKit`.
- `NFTKit` still owns NFT-specific refresh orchestration and `NFTProviderFailure`, which is correct because that code speaks in collection refresh semantics, receipts, and fetcher errors.
- The token provider no longer reaches upward into `ChainProviders` or `NFTKit`; ProviderKit keeps its own tiny chain capability guard and local string normalization helpers so the dependency graph stays one-way.
- The migration was verified with a full app build and the provider-focused app tests: 33 tests passed across provider configuration, Retry-After parsing, Alchemy NFT responses, token balances, token holdings pagination, retries, and error mapping.

The memorable bit: moving pipes is not the same thing as redesigning the kitchen. The best package migration is boring in exactly the right way: same faucets, same water pressure, cleaner basement.

## Feature Package Migration Maps: Label the Moving Boxes Before Lifting Them

This planning pass drew context-free migration maps for four package candidates: `AuralisShellCore`, `NFTLibraryFeature`, `MusicFeature`, and `AccountsFeature`.

- `AuralisShellCore` is the front-desk rulebook: shell state, actions, route effects, and deep-link replay belong there, while live service construction stays in the app target.
- `NFTLibraryFeature` is the gallery wing: NFT listing, detail, collection views, cards, sort controls, and marketplace handoff can move together without dragging provider plumbing along for the ride.
- `MusicFeature` is the AuraPlay room getting real walls: the shipping music UI and service protocols fit a package, but the long-lived audio engine should stay behind a playback protocol until the boundary proves itself.
- `AccountsFeature` is the check-in counter: gateway, address entry, guest passes, account switching, and account presentation make sense as feature UI, while `AccountsCore` and `AccountStorage` keep owning the lower floors.

The lesson is satisfyingly practical: a package name is not a wish. It becomes architecture only when the migration doc says what moves, what refuses to move, what the package may import, and what the first session should do without needing a tour guide.

One extra rule got nailed to the wall before anyone starts moving files: use real imports, not compatibility typealiases. When a type moves into a feature package, the app and tests should import that package directly. Typealias bridges feel convenient in the moment, but they turn module ownership into a stage set: it looks like a wall until somebody leans on it.

## AuraUI: The Shared Stage Gets A Name

The feature-package plans exposed an awkward truth: every future feature wanted the same Aura primitives, but those primitives were still tucked inside the app target like reusable stage lights stored in one actor's dressing room.

- `AuraUI` now exists as a root-level local Swift package for shared presentation vocabulary: colors, text wrappers, icon helpers, haptics, surface cards, action buttons, empty/error feedback, pills, and trust labels.
- The package layout is intentionally flatter than the app's old `Aura/Primitives` nesting. Shared UI should be easy to browse because it is the drawer every feature package will open.
- Gateway-specific scenery stays app-side for now. A reusable button belongs in `AuraUI`; a specific onboarding background still belongs to the onboarding surface until it proves otherwise.
- The broad call-site migration is now complete. App, Gas, Music, Receipt, and test files import `AuraUI` directly instead of relying on app-target duplicate definitions.
- The old app-local primitive files, `Text+Font.swift`, and `Colour.swift` are gone. `AuraScenicScreen` stays app-side because it still composes the gateway-specific background.
- One namespace lesson arrived immediately: `Color.secondary` is already SwiftUI vocabulary, so the Aura palette uses `Color.auraSecondary` rather than fighting the framework for the same name.

The useful lesson: shared UI is a stage kit, not a feature. Once it has a name and a clean shelf, feature packages can borrow the same lights without dragging the whole theater around.

## AuralisShellCore: The Front Desk Rulebook Moves Out

The shell finally got its own package-shaped office. `AuralisShellCore` now owns the small but important rules that decide what the app is trying to do before any SwiftUI screen gets involved: active selection, shell actions, route effects, deep-link values, parsing, and pending deep-link replay.

- The first pass moved value types and parser/resolver logic only. `ShellStore` stayed in the app target because it still talks to live app collaborators, SwiftData accounts, NFT refresh, receipt logging, and the router effect handler.
- `AppRouteError` moved into the shell package, but the Aura trust-label presentation stayed app-side as an extension. That keeps the core error transport clean while letting the UI keep its warning sticker.
- `ShellState.activeAccountID` stopped using SwiftData's `PersistentIdentifier` and now stores the account address. That is the shell's stable identity key already, and it avoids dragging SwiftData into the shell core just to know whether an account is active.
- Parser and pending-replay tests moved into `AuralisShellCoreTests`, so the rules can be tested without launching the app target once the package is attached to the Xcode project.

The gotcha: moving source files is only half the migration. Xcode still needs the local `AuralisShellCore` package product added to the app and test targets through the project UI. Until that package graph is wired, `import AuralisShellCore` is like putting a new desk in the building but forgetting to add it to the directory.

## AuralisShellCore: The Front Desk Runs Its Own Shift

The migration is now the real thing, not just a forwarding address. `ShellStore` moved into `AuralisShellCore` with the collaborator protocols it needs to stay honest: selection persistence, account resolving and mutation, refresh coordination, deep-link replay, router effects, receipt logging, and a clock. The package now owns the rules; the app target owns the plugs in the wall.

- `ShellStore` no longer imports SwiftData or NFT service code. It talks to protocols, which is the architectural equivalent of asking for "someone who can unlock the door" instead of depending on a specific locksmith with a specific van.
- The app-side `ShellCollaborators.swift` is now an adapter shelf. SwiftData account stores, user defaults, NFT refresh, receipt logging, and `AppRouter` effect handling stay there because those are live infrastructure, not shell law.
- `ShellStoreTests` moved into `AuralisShellCoreTests`, so account switching, chain changes, logout, refresh timing, route errors, and deep-link replay are tested at the package boundary instead of sneaking through the app target.
- One practical test wrinkle: `swift test` from Terminal still tries to compile the iOS-only primary models as a macOS package and trips over `UIKit`. Xcode builds the iOS scheme cleanly, so package tests should run through an iOS-capable Xcode test destination or test plan entry rather than plain macOS SwiftPM.

The useful lesson: a state machine package should be a rulebook, not a tiny copy of the app. If the package can explain what should happen without knowing how SwiftData, NFTs, receipts, or navigation views are physically wired, the boundary is doing its job.

## NFTLibraryFeature: The Gallery Gets Its Own Wing

The NFT library migration started turning the gallery from an app-side hallway into a feature package with its own walls. The tricky part was refusing to move the basement machinery with it.

- `NFTLibraryFeature` now owns the NFT gallery vocabulary: route values, sort fields, collection-detail presentation, loading and empty states, detail UI, collection UI, feed cards, token-list UI, cached image loading, and external marketplace confirmation.
- The app target still owns SwiftData queries, `NFTService` refresh orchestration, receipt-backed event logging, and `openURL`. Those are the electrical outlets in the building; the gallery should plug into them, not install a second breaker panel.
- The app-side NFT wrappers are now thin adapters. They scope NFTs with SwiftData, translate `AppRouter` routes into `NFTLibraryRoute`, and hand the package a dependency closure for trusted external-link opening.
- Package tests cover the logic that should not require an app launch: collection filtering, display fallback copy, image URL preference, route hashability, and sort metadata.

The gotcha was pure Xcode reality: adding a local package product to the app target requires project graph wiring. We deliberately did not hand-edit `project.pbxproj` while Xcode was open, because that is how an otherwise tidy migration turns into a project-file incident. The next step is to add `NFTLibraryFeature` through Xcode's package UI, then run the app build so the new imports resolve in the app target.

## NFTLibraryFeature: One Image Loader, Two Honest Homes

The cleanup pass after the NFT library move found the classic migration leftover: the gallery had moved into its own wing, but one old moving box was still sitting in the app hallway.

- `Auralis/Aura/Newsfeed/Components/NFTImageView.swift` was the duplicate. The real NFT image loader/cache/view now lives in `NFTLibraryFeature` as `NFTImageLoader`, `NFTImageCache`, and `NFTCachedAsyncImage`, so the app-local copy was retired.
- The surprise was that AuraPlay had been borrowing the same old file for a generic `CachedAsyncImage`. That was not NFT library code; it was music artwork plumbing wearing an NFT file path. We gave AuraPlay its own small playback-local image wrapper so music no longer depends on a gallery component by accident.
- The image-loader tests moved with the image-loader behavior into `NFTLibraryFeatureTests`. The app test file was renamed around what it still actually tests: token-holdings provider pagination and warning behavior.

The lesson is neat and transferable: when moving a feature package, do not just ask “who imports this?” Ask “which product is this type really serving?” A duplicate file often contains two truths tangled together. Separate the truths, then delete the duplicate.

## MusicFeature: AuraPlay Finally Moves Into Its Own Room

AuraPlay is no longer just leaning on a package boundary; the shipping music surface now lives behind it. The package owns the root view, detail screens, mini player, now-playing sheet, presentation models, service protocols, and the dedicated AuraPlay SwiftData projection helpers. The app target keeps the wall plugs: `AudioEngine`, receipt storage, source NFT snapshots, account sync state, and live SwiftData contexts.

The most important move was the playback bridge. `AudioEngine` did not move into `MusicFeature`; instead, the package asks for `AuraPlayPlaybackPresenting` and the app teaches `AudioEngine` how to speak that language. That keeps AVFoundation lifetime and queue mechanics in the app while letting the UI compile from the feature package.

The migration also retired a subtle old shortcut: the music tab used to enter through `AuraPlayTabRootView` in the app target. `MainTabView` now hosts `MusicFeatureRootView` directly and builds a package dependency bundle from live app adapters. That is the difference between “we have a package” and “the app actually uses the package.”

War story: the test runner got sticky during two older Wave 2 persistence tests and left an `Auralis.app` process hanging around like a stagehand who missed the blackout cue. The build was clean, and the focused root/presentation/schema tests passed, but those long-running persistence cases should be revisited separately if they keep wedging the Xcode test harness.

## AccountsFeature: The Front Desk Moves Out Of The Lobby

The AccountsFeature migration is now past the halfway-house phase. The gateway, address entry, guest passes, QR scanning, account switcher presentation, address validation, pasteboard handling, and chain-scope planning now compile from `AccountsFeature`. The app target still keeps the live wiring: SwiftData queries, concrete account stores, real ENS resolution, and shell actions.

- The package owns the front-desk experience: collect an address, validate it, scan a QR code, offer guest passes, and present saved accounts. It asks for small protocols like `AccountActivating`, `AccountSwitching`, and `AccountENSResolving` instead of knowing about `ModelContext`, `ShellStore`, or the concrete ENS/web3 stack.
- The app-side `AccountSwitcherHostSheet` is now the adapter tray. It feeds SwiftData accounts into the package view and wraps `AccountStoring` so the feature can save chain preferences without importing `AccountStorage`.
- ENS was the useful boundary lesson. Pulling the real `ENS` module into `AccountsFeature` dragged web3/C-module planning noise into a UI package. The fix was to make AccountsFeature speak a tiny account-facing ENS protocol and let the app translate real `ENSResolutionError` values at the edge.
- Xcode had one packaging quirk: the active package source list initially ignored newly added files, so the migrated feature API was folded into an existing compiled package source file for this pass. That is not elegant architecture, but it kept the module boundary honest and the build green. A later cleanup can split that large file once Xcode's package graph is refreshed cleanly.

The senior-engineer takeaway: a feature package should know the shape of the user promise, not the shape of the basement. If account UI can activate, switch, and resolve accounts through narrow protocols, it can move rooms without dragging SwiftData, shell state, or provider plumbing behind it.

## AccountsFeature: The Front Desk Gets Its Closing Checklist

PKG-004 is now closed in the important architectural sense: the account-entry package owns the user-facing rules, and the app target owns the live building wiring.

- The final hardening pass added package-owned presenters for ENS resolution states and account activation errors. That matters because the entry flow now has a tested vocabulary for “verified,” “stale cache,” “mapping changed,” and “save failed” instead of scattering those sentences through SwiftUI callbacks.
- The account switcher also got its own ordering presenter. The app still performs the SwiftData query, but the package owns how saved accounts are presented: recently selected accounts first, then newest additions, then address tie-breaks. Think of it like the app handing over the guest list while the front desk decides the order of the clipboard.
- `ProfileCardView` intentionally stayed home. It may sound account-ish, but it now owns Home-specific avatar generation, ENS display refresh, Aura artwork prompts, and dashboard composition. Moving it would be like packing the lobby mural with the check-in forms just because both are near the front desk.
- The plan doc now records that decision directly, which is the real migration hygiene lesson: “not moved” should be a named boundary decision, not a mystery for the next engineer to rediscover.

The memorable bit: a migration is not finished when the files are merely in a new room. It is finished when the new room owns its rules, the old room owns only the adapters, and the map says why the furniture that stayed behind belongs there.

## Package Migration Plans: Stop Moving Furniture Without A Floor Plan

This pass turned the next wave of package candidates into implementation contracts under `Auralis/docs/plans/PackageMigrations/`. The important architectural move was turning “move the furniture over there” into “here is the floor plan, here are the doors, and here is the list of pipes nobody gets to cut.” `ContextCore` comes before `ContextInspectorFeature`, `ApprovalsCore` comes before any speculative approvals UI, and app composition stays in the app target even when feature UI moves out.

- `ReceiptsFeature`, `SearchFeature`, `TokenHoldingsFeature`, and `GasFeature` now have concrete package layouts, public APIs, adapter contracts, dependency graphs, and test ownership. That means implementation should be boring in the best way: move the code, wire the adapters, prove parity.
- External links got the most important non-move decision. The policy and confirmed-open flow already live in `OperatorCore`, so creating `ExternalLinkFeature` right now would duplicate the map instead of improving the route. The real task is to move the wallet-app probe protocol into `OperatorCore` and keep `UIApplication`, receipts, and `openURL` as app-side adapters.
- `ApprovalsCore` is deliberately just core vocabulary for now. The current app only blocks policy-controlled actions in Observe mode; inventing a full approvals UI before real agent approval flows exist would be architecture theater.

The lesson sharpened a bit: a migration plan is not implementation-ready until it names the exact DTOs, protocols, package dependencies, access levels, async/cancellation behavior, and app adapters. Otherwise the next engineer is not implementing a plan; they are doing architecture live on stage with a stopwatch running.

## ApprovalsCore: A Permission Slip Before The Inbox Exists

The first approval migration deliberately avoided building an approval center, queue, or review screen. Instead, `ApprovalsCore` now gives the future workflow a small shared vocabulary: immutable approval request IDs, request metadata, requesters, actors, risk levels, audit references, and decisions. It is the permission-slip form, not the front-office filing cabinet.

- The package imports `CapabilitiesCore` directly for `CapabilityID`. No typealias bridge was added, because the point of this migration is to make package boundaries explicit instead of leaving forwarding signs around the codebase.
- Validation is intentionally boring: request IDs, titles, and summaries are trimmed before storage; empty values throw `ApprovalValidationError`; nil expiry never expires; finite expiry flips at `now >= expiresAt`.
- The app's current Observe-mode policy behavior stayed untouched. Signing, spending approval, and transaction drafting are still denied by the existing policy gate, and `ApprovalsCore` does not sneak into runtime flow until there is a real approval workflow to model.
- Tests live with the package using Swift Testing, matching the repo's direction for new unit coverage. One local tooling wrinkle: this machine's selected command-line toolchain is `/Library/Developer/CommandLineTools`, which builds the package source but does not expose the `Testing` module. Run the package tests from an Xcode toolchain or destination that includes Swift Testing.

The useful architecture lesson is restraint. A core package should name the durable nouns and rules first. Storage, routing, receipts, notifications, signing, and UI can arrive later with their own adapters instead of being guessed into existence today.

## SwiftData Undo: Do Not Let The Janitor Rebuild The Museum

The account-removal undo test exposed a nasty SwiftData edge case: deleting an account also deletes scoped NFTs, token holdings, and search history. Letting SwiftData record every raw delete into `UndoManager` looked convenient until `context.undoManager?.undo()` tried to create a snapshot for an `NFT.Contract` relationship and crashed with `_FullFutureBackingData`.

The fix was to treat destructive account removal like packing a museum exhibit before renovation. `SwiftDataAccountStore` now takes a small restoration snapshot of the account and its scoped support data, disables automatic undo registration while the destructive delete runs, clears any raw SwiftData undo entries that slipped onto the stack, and registers one explicit undo action that reinserts fresh model instances. The restore action also disables undo registration so SwiftData does not try to create redo snapshots for relationship futures while undo is already in progress.

The lesson: Undo for graph-shaped SwiftData deletes should be a controlled transaction, not a replay of every broom stroke. Snapshot the user-visible state you promise to restore, then make the undo stack hold that promise directly.

## Privacy Reset Tests: Shared Defaults Are Sticky Notes, Not Test Fixtures

The privacy reset suite had the kind of failure pattern that makes engineers squint: targeted runs passed, but Xcode could still report failures after broader or interrupted test sessions. The production reset path was doing the right big things, but part of the test setup used stable `UserDefaults` suite names for pinned home actions. That meant an interrupted run could leave a little sticky note behind for the next run to find.

The fix was intentionally small. `PrivacyResetServiceTests` now creates UUID-backed pinned-item stores, matching the isolation style already used by `HomePinnedItemsStoreTests`. Each test gets a clean preference room instead of borrowing a room with yesterday's notes still on the desk.

The lesson: in-memory SwiftData containers are only half the isolation story. If a test also touches `UserDefaults`, files, caches, or singletons, those need their own fresh sandbox too. Otherwise the bug report starts looking haunted even when the app code is innocent.

## EOAccount Names: Property Observers Do Not Guard The Door

`EOAccountTests` caught a subtle SwiftData trap: `EOAccount.name` looked like it had a perfectly reasonable `didSet` observer that refreshed `normalizedName`, but `@Model` properties do not reliably honor property observers. The result was an account that could change its display name while its indexed search key stayed stuck on the old value.

The fix was to make the public `name` API computed and back it with a persisted `storedName` field using `@Attribute(originalName: "name")`. Now direct assignments like `account.name = "ENS Alias"` update both the stored display name and the normalized search key in one place, while the underlying store keeps the existing column identity.

The lesson: when a SwiftData model needs an invariant, put that invariant in an explicit setter or method you control. A property observer on a persisted model field is more like a decorative lock than a security system.

## Account Deletion: Check Which Storage Room Exists

`P0201FlowValidationTests.validatesPrimaryWatchAccountFlow` hit a crash that looked like account deletion but was really a schema contract mismatch. The flow test used a lean SwiftData container with accounts, NFTs, tags, and receipts. `SwiftDataAccountStore` removed an account, then helpfully tried to delete `TokenHolding`, `MusicLibraryItem`, and `SearchHistoryRecord` rows too. SwiftData quite reasonably replied that this container had no such entity.

The fix was to make account-scoped cleanup ask the container's schema before touching optional support models. In the full app store, account deletion still purges token holdings, music library rows, search history, NFTs, and orphaned NFT shared models. In smaller package or flow-validation containers, it skips models that are not part of that schema instead of crashing.

The lesson: a reusable storage adapter should not assume every test or package container is the production warehouse. If cleanup spans optional feature data, check the schema before opening that door.

## Music Receipts: Nested Payloads Need Their Own Passport

`MusicReceiptEventLoggerTests` exposed a receipt sanitizer mismatch that only showed up inside nested payload objects. The top-level `playlistTitle` field was explicitly classified as a public label, but the same title inside `afterSummary` traveled as a plain object value. Once the sanitizer unpacked that object, it had to infer the field kind from the key and treated `playlistTitle` as an unknown string. Unknown strings get redacted, so the receipt said the playlist title was `<redacted-unclassified-string>`.

The fix was to teach the sanitizer that nested keys containing `title` are bounded freeform display text. That keeps short titles useful in receipts, still truncates long titles, and does not weaken sensitive fields like `reason`, errors, URLs, tokens, or wallet addresses.

The lesson: metadata attached to a top-level receipt field does not automatically follow values into nested dictionaries. If a nested object has strings that should survive sanitization, the inference rules need to know what those keys mean.

## AuraPlay Sync: Dictionary Initializers Are Not Dedupers

`AuraPlayPersistenceWave2Tests.requestBundleDeduplicatesAndSortsSnapshots` found a very Swift-shaped trap: `Dictionary(uniqueKeysWithValues:)` sounds like a handy way to build a lookup, but it is actually a promise that the input has no duplicate keys. Break that promise and it does not politely pick a winner; it crashes.

The AuraPlay sync request builder receives NFT snapshots from a refresh boundary, where duplicate IDs are not exotic. They can happen when upstream data is noisy or when a later snapshot supersedes an earlier one. The fix was to use `Dictionary(_:uniquingKeysWith:)` and make the later snapshot win, then sort by ID before building media-item upsert requests.

The lesson: when production data can contain duplicates, make the conflict policy explicit. A fatal dictionary initializer is a great assertion for impossible states and a bad broom for messy provider data.

## Phase 2 Audit Triage: The Tickets Are Still Standing

This validation pass took the Phase 2 architecture tickets back to the actual code instead of trusting the old audit wording. The result was blunt: none of the eight tickets were imaginary.

- The package-boundary tickets are real. The app still imports package products that are not explicit app target dependencies, `NFTKit` still reaches into `ReceiptStorage`, and `TokenStorage` still leans on `NFTKit` for provider/domain vocabulary and normalization.
- The view-boundary tickets are real too. Several SwiftUI views still build `FetchDescriptor`s, fetch/count directly, or listen to `ModelContext.didSave`. That is convenient in the way keeping tools on the kitchen counter is convenient: fine for one sandwich, annoying once the whole restaurant opens.
- The composition ticket has made progress, not disappeared. `ShellBootstrapDependencies` and `ShellServiceHub` are a useful halfway house, but `MainAuraView` and `MainTabView` still know enough about bootstrapping, audio receipts, AuraPlay storage, and context construction to keep the ticket alive.
- Address parsing and local storage classification remain the two quiet drift risks. Ethereum address normalization still has multiple homes, while wallet-ish state still spans `UserDefaults`, `@AppStorage`, SwiftData, and view state without a documented tier map.

The lesson: validating a ticket is not the same as agreeing with its original drama level. Good triage asks, “Does this still describe the code?” and then adds receipts. In this case, the answer was yes across Phase 2, with ARCH-005 carrying the important footnote: partially addressed, still not done.

## Phase 1 Security Tickets: The Erase Button Has To Mean It

The Phase 1 audit cleanup tightened four places where the app was close to safe but not quite honest enough.

- Privacy reset now clears the credential store through an injected dependency, and Keychain delete failures become typed reset phase errors instead of disappearing behind a friendly “done.” An erase button should behave like a shredder, not like a desk drawer with a nicer label.
- Receipts grew an integrity envelope: account-scoped sequence IDs, payload hashes, previous hashes, chain hashes, and a Keychain-protected chain head. SwiftData still stores the timeline, but the protected head gives verification something outside the mutable table to compare against.
- External links stopped treating an approved host as permission for every possible path and query string. The policy now has route rules, confirmation display drops raw query and fragment data, and receipt logging records a query-free URL.
- Provider failures now have public error codes. Receipts no longer need `String(describing:)` from raw provider errors to say “rate limited,” “bad provider auth,” “unavailable,” or “invalid response.”

The lesson: security work often starts as “add one check,” but the real fix is usually making the contract explicit. What gets cleared, what gets logged, what can be opened, and what can be trusted all need names the code can enforce.
## Shell Selection Keychain: The Valet Needs To Hand Back A Ticket

The active wallet selection moved out of `UserDefaults` and into Keychain, which was the right storage room for wallet metadata. But the first pass had a dangerous valet problem: it accepted your keys, nodded politely, and never told you if the key hook fell off the wall. Keychain reads, writes, updates, and deletes were synchronous on the main actor, and several `OSStatus` failures were ignored.

The fix made the storage contract honest. `ShellSelectionPersisting` is now async and throwing, backed by a dedicated Keychain actor that checks `errSecSuccess`, `errSecItemNotFound`, `errSecDuplicateItem`, update failures, decode failures, and delete failures explicitly. The shell now surfaces persistence failures as route errors instead of pretending a failed load means “no saved wallet.” Privacy reset also treats saved-selection clearing as a real local-preferences phase, so a failed Keychain delete blocks the success message instead of leaving old wallet metadata behind.

The tests got their own lesson too: production Keychain services and default `UserDefaults` are not test fixtures. The dependency-builder tests now inject isolated shell selection persistence and UUID-backed pinned-item stores, while a focused Keychain test uses a one-off service name to prove save, duplicate update, load, and clear behavior without touching the production slot.

The lesson: persistence APIs should either complete the promise or return the claim ticket saying they could not. Silent storage failure is not graceful degradation; it is a future launch bug wearing a calm face.

## Release Secrets: The Factory Door Now Checks The Badge

The security ticket for Release API-key validation was half true in the most dangerous way: the journal remembered a build gate, but the Xcode project did not actually have one. That meant an archive could still leave the factory with `AURALIS_ALCHEMY_API_KEY` missing or replaced by placeholder text, and the app would only complain later when networking tried to use it.

The fix was to make the factory door check the badge. `ValidateReleaseSecrets.sh` now runs from the Auralis target, exits quietly for non-Release builds, and fails Release builds when the Alchemy key is empty or shaped like placeholder scaffolding. It deliberately does not print the key, because a build log should not become a tiny secrets bulletin board.

The lesson: documentation is not a control. If a release rule matters, wire it into the build so the machine enforces it every time.

## Primary Models: The Toolbox Stopped Packing A Couch

`AuralisPrimaryModels` had become the everything drawer: portable wallet and chain vocabulary lived next to SwiftData tables, and `Tag.swift` even imported SwiftUI and UIKit just to help with colors. That meant a package could ask for a tiny domain noun and accidentally drag in UI frameworks and persistence furniture.

The first architecture cleanup moved the clearly owned tables to the packages already responsible for writing them. `StoredReceipt` now lives in `ReceiptStorage`, `TokenHolding` lives in `TokenStorage`, and `AuraPlayMediaItem` lives in `MusicFeature` persistence. The app schema still opens the same model names, and the remaining primary SwiftData models stay put for now because `EOAccount`, `NFT`, `Tag`, `Playlist`, and the music/search rows are still tied together by persisted relationships.

The pure side got some fresh vocabulary too: `NFTIdentity`, `NFTMetadataSnapshot`, `TagValue`, `AccountSummary`, `TokenHoldingDescriptor`, `PlaylistDescriptor`, and `SearchHistoryValue` are the small, Sendable shapes feature packages can pass around without borrowing a database table. Boundary tests now check that the primary package does not import SwiftUI/UIKit and that moved storage-owned models do not creep back.

The lesson: package boundaries work best when the noun you import is the noun you meant. If you want a tag value, you should not have to invite a SwiftData model and a color renderer to dinner.

## ERC-20 Sync: The Bouncer Has To Stay At The Same Door

The ERC-20 holdings cleanup moved provider fetching and SwiftData persistence out of the SwiftUI view and into a use case, which was the right direction. But the first pass quietly changed the lifetime of the stale-sync guard. The old view owned one `ERC20HoldingsSyncCoordinator`, so when a newer wallet refresh started, the older provider response was stopped before it could write stale rows. The extracted version accidentally built a fresh use case, and therefore a fresh coordinator, for every sync call. That meant each request had its own bouncer and nobody was watching the whole line.

The fix was to keep one syncer alive for the ERC-20 root view's lifetime while still leaving the provider and persistence work out of the view. Now overlapping syncs share coordinator state again, so a slow old response is dropped before persistence. We also separated native balance persistence from ERC-20 token support: Solana, Ethereum, and future chains can all have a native balance, even when their token standards differ. Native balance is the wallet's cash drawer; ERC-20 rows are just one kind of shelf next to it.

The lesson: dependency injection is not only about what object you pass, but how long that object lives. If a collaborator protects ordering, cancellation, deduping, or stale-result suppression, its lifetime is part of the correctness contract.

## CONC-002: The Main Actor Is Not A Loading Dock

The CONC-002 cleanup pulled two service paths off the UI actor: NFT fetching and AuraPlay library sync. Both had been wearing `@MainActor` like a high-vis vest because some caller nearby cared about UI state. That made the main actor a loading dock for pagination, retries, deduping, projection, and SwiftData sync work. It worked, but it meant the checkout line and the warehouse forklift were sharing one lane.

NFT fetching now reports progress as explicit `Sendable` values instead of exposing mutable fetcher properties for `NFTService` to read. `NFTFetcher` became an actor, owns its own loading/retry/pagination state, and returns an `NFTFetchInventoryResult` that says whether cleanup is safe. `NFTService` stays `@MainActor` because it is observable UI state; the fetcher does not.

AuraPlay got the same boundary treatment. The public sync protocol is no longer main-actor isolated, the live sync service can coordinate its `@ModelActor` stores off-main, and pure request projection moved behind a tiny `LibraryProjectionService` actor instead of using a detached task. Detached tasks are useful tools, but for this case an actor is a better kitchen station: named, injectable, and easier to reason about.

The lesson: `@MainActor` should describe UI ownership, not general convenience. When a service needs to report progress to a view, send progress across the boundary; do not move the whole warehouse onto the main actor just because the display board lives there.

## NFT Refresh Freshness: Half A Delivery Is Not A Stocked Shelf

The async NFT refresh refactor taught the fetcher to say whether it really completed the full provider walk. That was the right new receipt, but `NFTService` was still treating every persisted batch as a successful full refresh. A partial delivery could update the freshness timestamp, which made the UI think the collection shelf had just been restocked even if the provider only handed us one crate and left the rest on the truck.

The fix was to separate "we persisted what we got" from "the refresh is fresh." Partial refreshes can still persist useful data, but they no longer run stale cleanup and no longer update `lastSuccessfulRefreshAt`. Cleanup also now appears after persistence in the service phase order, not before it, so the progress state tells the truth about what work is actually happening.

The lesson: progress flags are contracts, not decoration. If a lower layer tells you the inventory is partial, the cache freshness layer has to believe it.

## Account Switcher: The Waiter Should Wait For The Kitchen

The account switcher had a clean architectural instinct: current-chain changes should go through `ShellStore`, not sneak around the shell and persist from the sheet. But the first version handed the order to the kitchen and immediately cleared the table. If the shell could not save the new chain, the sheet had already dropped its pending state and could not show its own failure path.

The fix made the callback async and throwing. The sheet still does not own current-chain persistence, but it now waits for the shell to confirm the selected chain before clearing the pending picker state. Preferred-chain changes remain local to the account store path; active current-chain changes use the shell path and keep the same visible failure behavior.

We also tightened two accessibility details while we were in the room: visible “Paste” stays the accessible command name for Voice Control, and each remove button now names the account it removes instead of repeating “Remove account” five times in a list.

The lesson: moving ownership up a layer is only half the job. The caller still needs a completion contract, or the UI starts acting like success happened before the owner has actually done the work.

## Security Audit Tickets: The Backlog Needed Its Missing Floors

The security and architecture audit ticket plan had a funny structural problem: the elevator opened on Phase 4, the sign at the lobby promised 24 rooms, and only 9 rooms had doors. The underlying audit reports still had the missing blueprint, so the plan now has the whole building again: Phase 1 security safety work, Phase 2 architecture boundaries, Phase 3 concurrency/state cleanup, Phase 4 wallet and agent safety, and Phase 5 testability maintenance.

The important part was not just adding volume. The tickets now keep the summary honest: 24 total, with 5 high, 14 medium, and 5 low items. Provider secrets, redaction, biometric Keychain protection, ENS storage, and future capability modes stay at the top of the pile. The rest of the backlog now has enough acceptance detail that someone can pick up a ticket without rereading three separate audit documents first.

The lesson: an audit backlog is only useful if its map matches the terrain. Counts, phases, severities, and acceptance checks are boring until they disagree; then they become the first bug to fix.

## Phase A: Trust The Code, Not The Victory Lap

The follow-up pass treated Phase 1, Phase 2, and Phase 3 as claims that needed receipts. Some claims held up cleanly: the password store really is biometric-bound in Keychain, the primary model and NFTKit package boundaries have real tests around them, `AppRouter` is main-actor isolated, and the broad front-desk `@MainActor` service problem is mostly gone.

A follow-up correction sharpened the threat model. Alchemy keys in URL paths are expected public client identifiers for this app, not private wallet secrets, and Ethereum addresses are public identifiers too. The remaining provider work is about saying that plainly, keeping Release validation, documenting quota/abuse controls, and making sure raw provider payloads or real secret-like fields do not wander into logs.

The code also pointed at unfinished business beyond that wording fix: ENS cache still needs an explicit policy/reset entry, shell-selection Keychain accessibility is implemented but not documented, receipt integrity still needs clearer guarantee language, and a few `Task.detached` calls remain in production paths.

So the plan now has a Phase A: not a new architecture adventure, just the cleanup shelf for work that survived verification. A readiness pass then split the board into three honest lanes: Phase A blocks the current Observe-only audit-clean ship target, Phase 4 blocks any future signing/custody/agent release, and Phase 5 is hardening unless release ownership promotes a ticket. The lesson is simple: a ticket is not complete because a paragraph says it is complete. It is complete when the code, tests, docs, and ship decision all tell the same story, including what the product deliberately treats as public.

## Provider Errors: Fingerprints Belong On The Evidence Bag

A-002 started as an NFT log hygiene fix, but the audit wording was bigger than one endpoint. The same Alchemy family also feeds ERC-20 holdings, native balances, and gas prices, and all of those paths could carry provider text forward as errors. That is like locking the front door while leaving the side doors with sticky notes that say "probably fine."

The fix moved provider payload classification into a shared `ProviderErrorPayloadSanitizer`. Known public copy, such as rate-limit messages with public wallet addresses, can pass through. Unknown bodies, operational JSON diagnostics, auth-looking fields, cookies, private keys, seed phrases, and unsafe JSON-RPC messages now become reason-coded SHA-256 fingerprints. The fingerprint keeps an evidence tag for debugging without stuffing the evidence itself into logs, route errors, or receipt-adjacent typed failures.

The lesson: public identifiers and provider payloads are different species. Wallet addresses can be useful daylight; raw upstream bodies are sealed envelopes unless the code has explicitly classified them.

## Accessibility Fixes: Do Not Board Up The Control Panel

The accessibility ship-readiness review found two sharp edges. First, Aura's surface colors had started using UIKit-flavored dynamic colors in shared package code, which is fine on iOS and a broken doorknob on macOS. The package now routes semantic colors through platform-specific `Color` helpers, so the surface system can ask for "surface" or "separator" without caring which framework owns the paint bucket.

The second bug was subtler: the NFT feed card made the whole page-sized card one accessibility element. That gave VoiceOver a convenient "open details" stop, but it also risked covering the real controls living inside the card, like the More Actions menu and the Show More Info button. The fix changed the card wrapper back into a container. The card still exposes its open action, but the control panel inside is no longer boarded up.

The lesson: accessibility grouping is power equipment. Use it to organize the room, not to drywall over the switches.

## Accessibility Phase 5: Give The Future Reviewer A Flashlight

Phase 5 was mostly about catching regressions before they become release-day archaeology. The preview shelf now covers the Gateway and the main app surfaces in large text and dark mode, including Settings through the profile route. These previews are not a substitute for a real device, but they are the flashlight a reviewer can grab before spelunking through VoiceOver, contrast, and layout checks.

We also swept the high-traffic accessibility strings that were still raw English literals. Icon-only controls and dynamic labels now go through `String(localized:)`, which keeps Voice Control, VoiceOver, and future localization from quietly drifting apart.

The lesson: testing artifacts are product infrastructure. A preview matrix does not make the app accessible by itself, but it makes accessibility regressions visible while the code is still warm.

## Accessibility Phase 1: The Labels Need To Travel With The Controls

Phase 1 turned the most important accessibility fixes from a checklist into behavior. The wallet address field now carries its validation state with it, so VoiceOver hears the problem at the same place a sighted user sees it. Failed submits also send focus back to the field. That is the form equivalent of putting the sticky note on the door that needs fixing, not on a wall three rooms away.

Loading states got the same treatment. Bootstrap now says what it is preparing, image generation becomes the active accessibility status while it blocks the Home screen, and the completion/failure announcements use the shared `AuraAccessibilityAnnouncer`. Receipts became one coherent row instead of a tray of disconnected labels, with the correlation ID still reachable through a custom action.

The music and NFT surfaces taught the Dynamic Type lesson again: big text is not an edge case, it is a different layout contract. Mini-player controls stack under metadata at accessibility sizes, track names get room to breathe, playback sliders speak real time values, and the NFT feed swaps full-screen paging for a normal summary list when page-height cards would trap content.

The lesson: accessibility metadata should live at the point of interaction. If state, validation, or progress changes somewhere else, users have to go hunting for it. Good UI keeps the announcement, focus, and action in the same neighborhood.

## Accessibility Phase 5 Follow-Up: A Preview Name Is Not A Simulator Switch

The Phase 5 checklist had two kinds of loose bolts. The first was straightforward: a few accessibility labels, hints, values, actions, and announcements were still raw English literals. Those strings are not backstage notes; they are user-facing copy for VoiceOver and Voice Control, so they now travel through `String(localized:)` like the visible text around them.

The second bolt looked like a preview feature but was really a documentation trap. SwiftUI lets previews set Dynamic Type and preferred color scheme, but the active SDK exposes Increase Contrast, Reduce Motion, and Reduce Transparency as read-only environment values. Naming a preview "Reduce Transparency" does not flip the system setting any more than writing "raincoat" on a sweater makes it waterproof.

So the preview names now say the quiet part out loud: use Canvas or device accessibility settings for those variants. The ticket also keeps manual evidence unchecked until someone actually runs those checks. The lesson: test scaffolding should never impersonate test evidence. A good checklist tells the next reviewer which switches the code can flip and which switches belong to the device.

## Accessibility Phase 1 Completion: The Tour Guide Gets A Microphone

The last Phase 1 pass focused on VoiceOver's first-mile experience. The QR scanner used to drop users into a camera room with no narrator and no side door. Now the sheet has a real title, an opening announcement, an Enter Manually escape hatch that returns focus to the wallet field, and a permission-denied message that says what happened instead of letting the camera fail like a silent locked door.

Artwork also got promoted from wallpaper to content. NFT hero cards, NFT details, Now Playing art, mini-player art, and music detail images now carry labels that travel with the track or token. The reusable music image helper no longer accepts a vague default; callers must say what the image is. That is the right pressure: if artwork matters enough to show, the code should know enough to describe it.

The rest of the pass made dense information easier to skim. Receipt facts, context receipts, and NFT token rows now read as coherent label/value summaries, while search, NFT detail, music detail, account entry, and Now Playing headings feed the VoiceOver rotor. Playlist creation now announces the async failures that used to appear only visually, and successful cover selection gets spoken as soon as processing finishes.

The lesson: accessibility is not a sprinkle at the end of a view. It is the tour guide, the signage, and the emergency exit. If any one of those is missing, the room may look beautiful and still be hard to use.

## Accessibility Phase 4: Big Text And Quiet Motion Get A House Style

Phase 4 was the accessibility pass where the furniture had to move, not just get better labels. Media-heavy screens love fixed artwork boxes because they look composed at normal sizes, but accessibility text sizes turn those boxes into reserved parking spaces for pixels. The fix was to let artwork shrink where the words need the room: NFT detail art, playlist covers, music detail art, collection rows, and Recently Played cards now choose smaller bounds when Dynamic Type gets large. Nearby label/value rows use `ViewThatFits`, which is basically the layout asking, "Can I sit side by side, or should I stack before someone gets elbowed?"

Color got the same treatment. Status still uses Aura's colors, but Differentiate Without Color now adds visible words or glyphs on gas, token, shell feedback, and trust-label surfaces. The point is not to make the UI louder for everyone; it is to make sure the warning survives when color stops being the primary channel.

The motion work pulled a loose convention into a reusable contract. `AuraMotionPolicy` now owns decorative loops and state-change animation choices, so new components have a paved path for honoring Reduce Motion. Haptics stay conservative for 0.1.0: they remain suppressed with Reduce Motion until the product has a dedicated setting. That decision is now documented instead of living as folklore in a tiny wrapper.

The lesson: accessibility settings are not edge-case flags. They are alternate operating conditions. Good components should have a house style for those conditions before the next feature arrives.

## Unit Test Audit: The Safety Net Has A Few Loose Knots

The GPT-306 unit test audit looked at the tests as code, not as a trophy case of green checkmarks. The suite is in good shape where it matters most: Swift Testing is the house style, SwiftData usually runs in isolated in-memory containers, and a lot of assertions check exact behavior instead of waving at "not nil" and hoping for the best.

The loose knots are mostly about time and shared state. A few async tests still wait by sleeping, which is like checking whether dinner is ready by staring at the oven for ten seconds. It works until the kitchen gets busy. URLProtocol fakes also carry static handlers, which are convenient but process-wide; Swift Testing likes parallel work, and global mutable test hooks are where flakiness likes to hide.

The audit is saved as `Auralis/docs/GPT-306-Unit-Test-Code-Audit.md`. The lesson: a unit test suite is refactoring infrastructure. It does not just need coverage; it needs determinism, isolation, and assertions sharp enough to catch the bug before the bug learns to look normal.

## Unit Test Phase 1: Stop Watching The Oven

Phase 1 turned the audit's trust-and-safety warnings into code. The sleepy tests were the first target. Gas pricing and NFT refresh tests no longer stand around asking "are we there yet?" in 10 millisecond loops; they now wait on the actual task or a continuation gate. That changes the test from a nervous hallway monitor into a doorbell: when the work starts or finishes, the test hears the signal directly.

The URL loading fakes got the same treatment. Image-loader and provider tests moved away from one shared `URLProtocol.handler` slot, because that slot is a hotel key left under the mat for every parallel test in the process. The new support helper builds mocked sessions with isolated handlers, and app-side tests have a filesystem-synced copy because Xcode project-file edits are not something to do while the IDE is open.

Privacy reset was the other big cleanup. The old mega-test checked a whole pantry of side effects at once: search history, receipts, holdings, NFTs, music rows, tags, shell selection, pinned actions, and reset collaborators. It now reads like a checklist where each item gets its own test. When one breaks, the failure points at the shelf that fell down instead of yelling that "the kitchen is wrong."

The lesson: deterministic tests are not just faster or prettier. They are more honest. A reliable test should wait for the thing it cares about, isolate the fake it owns, and fail with a label specific enough that the next engineer knows where to look.

One last validation pass caught a subtle version of the same bug wearing a nicer jacket. The new URLProtocol helper no longer had one global handler slot, but app-side registration initially read the handler dictionary and wrote it back in two separate lock operations. Parallel test startup could still drop a sibling session's handler, which looked like a mysterious `NSURLErrorBadServerResponse`. The fix was to mutate the registry under one lock.

The lesson inside the lesson: "thread-safe pieces" do not automatically make a thread-safe operation. If the operation is read-modify-write, the whole sandwich needs to stay under the lock.

## Phase 1 Follow-Up: The Fake Network Gets Its Own Booth

The first Phase 1 pass removed the obvious shared URL handler, but the stricter review caught the fine print: a dictionary keyed by session is still a process-wide coat rack. It is tidier than one hook, but parallel tests can still bump shoulders around it. The mock loader now creates a tiny `URLProtocol` subclass per mocked session and attaches the handler to that runtime class. Each test gets its own booth instead of a labeled hanger in the same hallway.

Privacy reset had a similar hidden wire. The test used a recording shell selection and fake credential resetter, but appending a receipt still walked through the live receipt store, which protects integrity heads with Keychain. That is a good production contract and a bad unit-test roommate. The fixture now uses the in-memory receipt integrity head store, so the test checks privacy reset instead of the simulator keychain's mood.

The UI audit failure turned into two lessons. First, launch fixtures should not depend on a live refresh leaving a seeded row alone; refresh cleanup is allowed to replace stale local NFTs. The external-link audit now opens a deterministic fixture harness. Second, XCTest's accessibility audit can report clipped child text inside a scrollable medium-detent sheet even when the sheet is reachable and scrollable, so the test documents that scoped false positive while keeping the rest of the audit blocking.

The lesson: isolation is not a slogan. If a test names a thing as local, its network, keychain, persistence, and route setup all need to be local too.

## Phase 1 Follow-Up: The Clock Moves Into The Fixture

The next determinism pass chased a quieter source of flakiness: tests that asked the wall clock what time it was and then tried to prove something about freshness, staleness, or creation dates. That is like measuring a shelf while someone is still carrying it across the room. Most days it works; on a loaded machine, the numbers can drift just enough to make a precise test look guilty.

Freshness now carries its reference date through `ContextFreshness`, `LiveContextSource`, `ContextSnapshot`, and `AppContext`, so labels like "2 min ago" and TTL checks can be tested against a frozen moment. Token metadata freshness got the same escape hatch, and search history can now record committed queries with a supplied timestamp. The production default is still "now", but tests get to bring their own clock.

We also tightened a couple of broad failure checks. A test that says "throws any Error" is a smoke alarm that goes off for burnt toast and a real fire with the same confidence. The NFT inventory path now expects the network failure shape it actually cares about, and malformed provider payloads assert `DecodingError` directly.

The lesson: time and errors are part of the contract. If the code means "older than this reference instant" or "this specific failure shape", the test should say that plainly.

## Unit Test Phase 3: One Kitchen, One Pantry Map

Phase 3 moved the SwiftData tests away from everyone sketching their own pantry map. App tests now route in-memory containers through `TestModelContainers` and named `TestSchemas`, so primary-store, receipt, token, search-history, and AuraPlay fixtures all point at a shared schema source. The one test that still builds a URL-backed container says so by construction: it needs a real persistent store boundary, not a second opinion about which models exist.

The persistence packages got sharper edge checks too. Account storage now proves duplicate inserts fail deterministically and overwrites sweep away stale account-scoped NFTs and tags. Receipt storage simulates an integrity-head write failure and then verifies the next successful receipt keeps sequence IDs monotonic. Token holdings pin the failure path that must leave existing rows untouched, and SwiftData adapter rollback now protects both inserted and mutated objects.

One marker test was retired instead of dressed up. `AgentIdentityCore` is currently a namespace-only package, so a test proving `String(describing:)` returns its type name was just a green sticker on an empty box. The package manifest no longer advertises an empty test target.

The lesson: schema drift is sneaky because it usually looks like harmless fixture setup. Good persistence tests should share the same map as production, then spend their energy on the weird cases where data can disappear, duplicate, or half-save.

## Unit Test Ship Readiness: The Test Lanes Get Road Signs

The last hardening pass cleaned up the boring-looking assertions that make debugging expensive. Optional chains inside `#expect` are now unwrapped with `#require` before the field checks, so a missing prerequisite fails like a missing prerequisite instead of pretending to be an ordinary equality mismatch.

Package SwiftData tests also got local schema authorities. The account, receipt, token, and SwiftData adapter packages each have one in-memory container helper for their test target. That keeps package tests honest about their dependency boundaries: they share a pantry map inside the package, but they do not reach back into the app target just because the app has a bigger map.

Finally, the Xcode scheme now has checked-in test-plan artifacts. Fast, architecture, and full regression lanes are visible as files instead of tribal memory, with explicit suite filters for the expensive architecture and slow checks. The lesson: a shipping test suite needs two things at once: sharp assertions inside the tests, and obvious road signs for how engineers are supposed to run them.

## Unit Test Phase 5 Follow-Up: The Fixture Drawer Gets Labels

The Phase 5 checklist said the duplicate fixture builders were gone, but a review found a few utensils still hiding in package drawers: local NFT and music item builders in `NFTKit` and `MusicFeature`. They were small, but that is exactly how fixture drift starts. One helper says "Fixture NFT", another says "Aurora Echo", and six months later a schema change turns into a scavenger hunt.

`NFTFixture` now knows how to build the odd cases the package tests needed: explicit IDs, absent collection metadata, descriptions, token types, image URL control, and raw metadata. `MusicLibraryItemFixture` can also represent sparse playback metadata without quietly inventing a URL. The tests now pull those shapes from the shared support package instead of sketching local copies.

One helper intentionally stayed local: `makeRefreshFixtureSnapshot`. That snapshot type belongs to `NFTKit`, while `NFTKit` already depends on `AuralisTestSupport`; moving the helper upward would make the packages chase each other in a circle. The lesson is that shared fixtures are a pantry, not a junk drawer. Put common domain ingredients there, but keep package-owned shapes in the package that owns them.

## AuraPlay Media Core: The Remote Control Leaves The Couch

The media packages had the right idea already: keep `AuraPlayMediaCore` boring and let audio/video do the AVFoundation gymnastics. This pass moved three more boring-but-important tools into that shared drawer. URL cache keys now come from one `CacheKey(url:)` initializer instead of two video helpers doing the same base64 dance. The default `URLSessionMediaDownloader` moved out of the audio engine, because downloading bytes is not an audio talent. And remote commands now pass through a neutral `MediaTransportControlling` dispatcher, so play, pause, toggle, seek, skip, next, and previous mean the same thing before each engine adds its local flavor.

The local flavor still matters. Video keeps its `.skip` seek tolerance for skip commands, and audio keeps its AirPlay queue behavior where previous restarts the current item. The core owns the common grammar; the engines still choose the accent.

The lesson: DRY is not about shoving everything into the basement. It is about noticing which code is a universal adapter and which code is a specialized appliance. Shared core should hold the adapter, not the whole entertainment center.

## AuraPlay Media Core: One Gateway List, Two Playback Surfaces

Gateway fallback graduated from a video-only protocol to a shared media contract. That matches the product reality: audio and video can point at the same NFT media source, and only the renderer changes. Video still uses fallback after a stall, like changing lanes when traffic stops. Audio uses the same resolver during cache downloads, like trying the next door when a gateway refuses to hand over bytes.

`MediaGatewayFallbackResolving` now lives in `AuraPlayMediaCore`, with a small ordered resolver for the simple case where composition already knows the candidate gateway URLs. Video keeps `VideoGatewayResolving` as a compatibility alias, while audio cache downloads accept the shared resolver and apply it to full, resumable, and progressive startup downloads.

Playback position persistence is different. The coordinator itself is generic enough to move eventually because it writes `PlaybackTick`, but audio does not yet have the same resume-position product behavior as video. Moving it before audio has a real store and restore flow would be tidy architecture with no customer behind it. The lesson: shared code should follow shared behavior, not just shared-looking shapes.

## AuraPlay UI Integration: Wireframes Before Wardrobe

The media engines now have a basic doorway into the app instead of living like impressive machinery behind a locked service panel. The Music tab moved from a migration placard to a real library surface: scoped collections, scoped tracks, play buttons, add-to-queue buttons, and navigation into the existing detail screens. It is not the final AuraPlay experience yet. It is the plywood stage that lets every cable reach the right place before anyone paints the set.

The important decision was to keep ownership honest. `MusicFeature` asks for callbacks like "play this item ID" and "open this collection"; the app target resolves those requests against the active wallet, chain, SwiftData NFTs, and `AuraPlayPlaybackRuntime`. That keeps the package from learning too much about app persistence while still letting the UI do useful work.

Now Playing gained a queue sheet plus visible integration placeholders for AirPlay route selection, cache/offline state, and visualizer output. Video got its first app-side wireframe too: a real `AuraPlayVideoEngine` player surface with URL load, play/pause, seek, speed, route picker, and honest disabled controls for PiP, fullscreen, offline downloads, captions, and audio tracks. The disabled controls are deliberate signposts, not fake features. A good integration pass should reveal the missing adapter seams instead of pretending they are already paved.

The lesson: wireframes are not throwaway if they connect real systems. They are scaffolding. You still remove the scaffolding before launch, but it lets engineers safely build the second floor.

## AuraPlay UI Ship Pass: The Control Panel Stops Bluffing

The AuraPlay requirements doc had already drawn the right line: ship the media UI that has real backing services, and hide the parts that are still just package contracts. This pass tightened the app to that promise. The audio Now Playing screen no longer leaves an error state as a dead warning icon; it gives the user a real Retry button that calls the active playback presenter. The visualizer also stopped pretending: it now either reflects live engine meter frames or clearly reports why the meter is paused.

Video got smarter without getting louder. The player now asks `VideoPresentationAnalyzer` what shape the source actually is, then keeps portrait, square, and landscape videos in their native framing instead of stuffing everything into a 16:9 shoebox. `HDRDetector` and `VideoPlaybackCapabilities` now feed capability rows too, so HDR and high-frame-rate badges appear only when the media reports those traits. That is the difference between a dashboard and a sticker sheet.

The smaller cleanup mattered too: remaining AuraPlay search/filter/sort and video row identifiers now come from `A11yID`, which keeps UI automation from depending on magic strings sprinkled through views.

The lesson: "ready to ship" is often less about adding controls and more about removing bluff. A production UI should either connect to a real system, explain a real state, or stay out of the user's way.

## AuraPlay Visualizer: The Meter Gets A Fuse Box

The visualizer was the last obvious AuraPlay UI item that had a real engine behind it but no honest app bridge. The audio engine already knew how to publish RMS and peak frames; the missing piece was a safe doorway into `MusicFeature`. We did not make the feature package import the audio engine. Instead, `MusicFeature` now owns a tiny presentation shape: normalized bar levels, live/paused state, and user-facing status copy. The app runtime translates engine frames into that shape.

The lifecycle is the important part. Now Playing starts the visualization stream only while the integration panel is onscreen, and it stops the engine tap on disappear. Reduce Motion acts like a circuit breaker: the UI keeps the visual status visible but pauses the live animation and stops the stream. That keeps the feature expressive without turning a decorative meter into a background battery tax.

The lesson: a live UI needs a fuse box, not just a wire. If something subscribes to real-time engine data, it should have a clear owner, a stop condition, and an accessibility policy before it ships.

### Follow-Up: The Fuse Learns About The Play Button

A code pass found a subtle lifecycle hole in that fuse box. The visualizer task was keyed to Reduce Motion, but not to the transport state. That meant a user could open Now Playing while a track was still loading, watch playback become live, and never get meter frames because the task had already decided "not playing yet." Pausing could also leave the engine visualization tap alive longer than the visible UI intended.

The fix was to make the SwiftUI task key include Reduce Motion, playback state, and current track ID, then stop the engine visualization tap from the runtime's pause, stop, and auto-advance paths. In restaurant terms: the meter no longer asks only whether the kitchen lights are dimmed; it also checks whether the stove is actually on.

## Xcode Beta Test Run: When The Same Pantry Appears Twice

The unit test suite hit a very beta-shaped pothole: app-hosted tests were loading SwiftData model classes from both `Auralis.app` and `AuralisTests.xctest`. The Objective-C runtime called it out plainly, then the tests did what duplicate model classes love to do: trap, abort, or hang in places that looked unrelated to the line being tested.

The fix for the fast lane was pragmatic. We turned off the app target's debug dylib for these runs, serialized the fast test target, and quarantined the specific hosted SwiftData tests that still crash under Xcode 26 beta with explicit `.disabled(...)` reasons. The tests are not gone; they are marked like wet paint so the next engineer knows the failure is runner infrastructure, not product behavior.

There was one real product-side miss mixed into the noise: `AuraPlayPlaybackPositionState` joined the AuraPlay SwiftData schema but had not been added to the local data storage policy table. That is now classified as wallet-scoped AuraPlay persistence, cleared with the AuraPlay reset phase. The lesson: noisy infrastructure failures can hide honest contract drift. First make the runner stop shouting, then listen for the one quiet assertion that still matters.

## AuraPlay Phase 5: The Discovery Pipe Gets Connected To The Faucet

Phase 5 already had the machinery: Alchemy, Helius, metadata fetch, schema parsing, classification, SwiftData persistence, and artwork prefetch. The missing shipping question was simpler and more dangerous: does the app actually turn the valve, or is the pipe just sitting proudly on the workbench?

This pass wired NFT discovery into the live music composition. `MusicAssembly` now hands the real `NFTSyncCoordinator` into `AuraPlayDependencies` when storage and provider keys are available. The AuraPlay root model uses that dependency during foreground refresh with the coordinator's 15-minute debounce, and pull-to-refresh bypasses the debounce for the current wallet and chain. In user terms: opening Music can quietly catch up, while an intentional refresh asks the provider right now.

The test fixtures also grew up. Alchemy pagination now exercises the ticket-sized 100 + 47 item shape, and Helius exercises 1000 + 250. Helius owner mismatches now leave a warning trail instead of silently dropping a questionable asset. That is like a bouncer refusing a mismatched ticket and writing it in the incident log, not just shrugging at the door.

The lesson: a feature is not shipped when its parts exist. It ships when composition, lifecycle triggers, release configuration, and tests all agree on how the current flows through the system.

## AuraPlay Phase 5 CI: The Test Lane Gets Its Own Guardrail

The Phase 5 discovery tests were present, but they were living in the package scheme while CI only drove the app's Xcode test action. That is like having a smoke detector in the kitchen and then only checking the hallway. CI now runs the `MusicFeature` package tests through Xcode before the app unit tests, so the Alchemy, Helius, metadata, classifier, artwork, and integration coverage stays on the shipping path without depending on plain `swift test`.

The validation pass found two good test-runner lessons. First, mocked POST requests may arrive at `URLProtocol` with an `httpBodyStream` instead of `httpBody`. The Helius recorder was looking in the wrong pocket, so every response looked like page 1 and the 1000 + 250 pagination fixture never stopped. Second, artwork prefetch is concurrent, so the test now checks that the right HEAD and GET requests happened instead of pretending the scheduler owes us a neat alternating order.

The lesson: CI gaps are rarely dramatic. They are usually one missing lane, one body stream, or one ordering assumption away from turning a real acceptance suite into decorative paperwork.

## AuraPlay Phase 9/10: The Contracts Stop Being Decorative

This pass closed the gap between what the Phase 9/10 plans promised and what the code actually did. The biggest offender was a familiar pattern: the typed query service, the bounded queue window, and the orchestrator presentation boundary all existed as well-shaped contracts that nothing called. `LibraryRootView` was quietly fetching every media row with `@Query` and sorting in computed properties, and `AuraPlayPlaybackOrchestrating` had zero conformances in the entire repository. A contract without a caller is a promise written on the workbench, not a load-bearing beam.

The cutover ran in dependency order. First the app grew `AuraPlayOrchestratorAdapter`, the live conformance that maps the app-private `PlaybackOrchestrator` into the public boundary, which immediately unlocked orchestrator-state mini-player visibility, the PiP restore banner, and a cold-launch restored-paused session that can actually resume (the orchestrator now knows when no engine has media loaded and reruns the full play path instead of silently no-opping). Then the Library moved onto service-fetched windows with near-tail paging, cached collection/creator grouping invalidated on sync completion, and taps that capture the exact sort/filter/offset context so the queue can lazily extend without ever reading live view state. The smaller debts came along: `syncAll()` on the protocol for honest pull-to-refresh, playlist membership checkmarks with toggle semantics, dimmed non-playable cells instead of hidden ones, one shared `SeekCoalescer` for scrubber and gestures, app-owned share/Safari/pasteboard presentation, and the hand-rolled explorer URL table replaced by the tested `ExplorerAdapter` catalog.

The test story had a twist worth remembering: `MusicFeature` had never actually compiled outside the Xcode workspace. The manifest was missing its `AuraPlayMediaCore` dependency and the Phase 9 views used iOS-only APIs without the platform shims, which is precisely why the package test plans looked empty. Fixing the manifest and routing platform-specific modifiers through `AuraPlayPlatformNavigation` made `swift test` real again — 95 tests in 16 suites in about five seconds, including 5000-item bounded-window proofs and `swift-snapshot-testing` baselines rendered through `NSHostingView`.

The lesson: when a plan says "service-backed" or "orchestrator-driven," grep for the conformance, not the type declaration. The type is the easy half; the wiring is the feature.

### Follow-Up: The Bouncer Still Needs The Sign On The Door

A production-readiness review caught two bundle-contract regressions that were easy to miss because the app still built. `Info.plist` had gained the new AuraPlay background fetch and Helius configuration keys, but the existing camera and photo-library usage strings disappeared in the same neighborhood. That is the kind of change that looks like harmless plist housekeeping until a user opens the active playlist cover flow and iOS shuts the party down at the privacy gate.

The release-secret validator had a smaller but useful lesson. Generalizing Alchemy and Helius validation through one helper was the right shape, but the app tests intentionally pin the provider-specific error text so release failures stay obvious in CI. The fix kept the helper while passing stable per-provider messages into it.

The lesson: bundle files are the coat check of the app. You can reorganize the tickets, but the camera, photo library, background task, URL scheme, and release-key promises all still need their numbered tags.

### Follow-Up: Do Not Hand SwiftData Models Through The Service Window

The next crash looked unrelated at first: NFT pagination tests exploded in `NFT.id` and `NFT.contract`, then shell dependency tests crashed while reading receipts. Same villain, different costume. App-hosted tests were loading some SwiftData model types from the app bundle and the test bundle, then asking SwiftData to cast or fetch across that split-brain pantry. The stack pointed at innocent lines because the real mistake happened earlier: a service boundary had let live persistence furniture cross into a test that only needed a clean receipt or provider shape.

The fix was to make those seams speak plain values. Provider responses now return `AlchemyNFTResponse.OwnedNFT` snapshots instead of app `NFT` models, and `NFTFetcher` decodes those snapshots into its inventory item shape without touching SwiftData. The shell dependency tests now inject a tiny actor-backed `ReceiptStore`, so they prove receipt logging is wired through the shared assembly without asking the simulator's duplicate `ReceiptStorage` classes to agree on identity.

The lesson is one worth taping above the prep table: SwiftData models are not DTOs, and test seams should not smuggle them around like serving trays. Use value snapshots for provider data, use protocol fakes for wiring tests, and reserve live SwiftData stores for tests that are actually about persistence.

### Follow-Up: The Media Ticket Needs To Keep The Attached Stub

A ship-readiness pass caught the kind of bug that feels tiny until the music tab goes quiet. Helius DAS was returning Solana assets with useful media file links, but the ProviderKit boundary converted those assets into an Alchemy-shaped value where `audioUrl` and `animationUrl` do not exist. The important clue was still inside `raw.metadata`, so the fix taught `NFTMetadataUpdater` to understand Helius' `content.files` and `content.links` shapes directly. The kitchen analogy: if the order slip has the sauce request in the notes, do not throw away the notes just because the main form has no sauce box.

The metadata fetcher got the same treatment as artwork prefetching. It now streams response bytes and rejects oversized payloads before building a giant `Data` blob. Metadata JSON is small by contract; if a server tries to send a sofa through the mail slot, the app should stop at the doorway.

The UI lesson was blunter. AuraPlay is a dark, immersive surface, but some rows and player controls were letting the host color scheme decide foreground colors. In snapshots that produced black text on a near-black player. The fix was not a redesign; it was making owned dark-surface text and controls explicit so the UI looks intentional wherever it is rendered.

## Search Assistant: The Librarian Gets Index Cards

The WWDC Spotlight search session landed on a truth Auralis was already orbiting: an LLM search feature is only as good as the shelves it can inspect. The app had a Spotlight-backed assistant, but the first quality gauge was a cardboard speedometer: the evaluation compared expected IDs to the same expected IDs. It proved the calculator worked, not that search found anything.

This pass gave the assistant proper index cards. Search requests now carry the classified query kind, so the Spotlight tool can ask for a smaller, sharper capability set. Token, NFT, and collection queries skip receipt machinery. Receipt-like activity questions get date support and the receipt rollup stage. Music and playable media questions get the media capability stage. The model still gets the same local app content, but with less irrelevant guidance rattling around in its context window.

Metadata also learned to speak in two voices. Humans still get readable lines like "Artist: Nova"; pipeline stages now get machine-readable tags like `auralis:mediakind=audio` and `auralis:receiptstatus=Failed`. That means custom stages no longer have to read prose with a magnifying glass when a labeled drawer is available.

The other missing piece was recovery. The Spotlight delegate used to politely acknowledge reindex requests and do nothing. Now it shares the active wallet/chain scope with the indexer and can rebuild all scoped items or specific requested identifiers. The lesson: if Spotlight asks you to restock the shelf, nodding is not inventory management.

## AuraPlay Phase 14: Stop Planning From An Old Map

This was not implementation work so much as cartography cleanup. The April Phase 14 ticket set had the right destination — settings, accessibility, privacy, errors, performance, App Review, and final regression — but it was reading from an old atlas. It talked like Settings still needed to be invented, like an app-wide `AppErrorBoundary` already existed, like `AuraPlaySchemaV2` was the migration target, and like every prior phase had its own integration-test suite lined up like train cars.

The current code tells a different, better story. `SettingsView` already owns EQ, custom EQ, normalization, AutoMix, offline downloads, Smart Shuffle, provider debug state, and privacy reset. AuraPlay errors are real but split across `MusicFeature` and `AuraPlayMediaCore`, not one grand app umbrella. The schema is still flat unless a future versioned migration lands. The regression net lives across actual targets: app-hosted Auralis tests, package tests, media-core tests, and video-engine tests.

So Phase 14 became a truth-alignment plan instead of a copy edit. The new plan keeps the general hardening functionality but pins every ticket to the code that exists, and the gaps doc now tracks the remaining release artifacts rather than pretending they are already signed off.

The lesson: old plans are like trail maps after a landslide. You do not throw them away if the mountain is still the mountain, but you absolutely redraw the path before sending the next person up it.

## AuraPlay Phase 14: The Exit Door Has To Actually Open

The hardening pass found two bugs that were hiding in plain sight because they were not dramatic crashes; they were exit-door problems. The first was in `HeliusNFTClientTests`: the owner-mismatch fixture returned exactly as many assets as the page limit. Production pagination did the right thing and asked for page two forever. The test looked like it was "hanging after everything passed," but really it had built a hallway with no end.

The second was in the video resource loader. Foundation's type resolver can manufacture dynamic identifiers for malformed MIME strings and even common extensions in this SDK/runtime combination. AVAsset loading wants stable content identifiers for common progressive files, so MP4 and QuickTime now get explicit mappings before the generic `UTType` fallback gets a vote. The kitchen version: if the label says "video/mp4", do not ask the pantry to invent a new shelf.

The release lesson is less glamorous but more important: green tests are not the same as a signed release. Phase 14 now has the audit/checklist artifacts it promised, and the automated gates are green across the app, MusicFeature, media core, and video engine. The remaining gates are intentionally marked as manual: VoiceOver traversal, physical-device playback, battery, AirPlay/PiP/routes, privacy reset on a real install, screenshots, and App Store upload warnings. That is not pessimism; it is how you keep a release checklist from becoming theatre.

## AuraPlay Settings: Knobs Need Wires

Phase 14's Settings gap had a classic control-panel smell: it is easy to add a slider, much harder to prove the slider is connected to machinery. The fix was to give the cache controls real wires. `MediaCacheManager` now owns a persisted cache cap, reports its current usage, and can clear unpinned cached files while leaving pinned or actively-read media alone. Settings just asks the runtime to do the work; it does not rummage through cache internals with a flashlight.

Playback defaults got the same treatment. Shuffle and repeat now have small, explicit defaults keys that `AuraPlayPlaybackRuntime` reads at startup. Video speed uses the existing `PlaybackSpeedController` key instead of inventing a second dial for the same engine. The lesson is the old studio rule: every knob on the board should move a real fader somewhere, or it should not be on the board.

The privacy reset failure path also stopped quoting raw framework errors to users. Technical details can live in logs; Settings now speaks in recovery copy. That is less flashy than a new feature, but it is the difference between an app sounding composed and an app blurting out its stack trace at the front desk.

## AuraPlay Phase 14: The Panic Button Gets A Real Circuit

The final hardening pass turned three release checklist red marks into actual code paths. Settings used to have a privacy broom that swept receipts, cache-ish support data, and local preferences while politely leaving saved wallet rows in the cupboard. That is useful, but it is not the same as the ticket's big red button. The app now has a separate all-wallet disconnect service that removes every stored account through the existing account-store removal seam, then runs the local privacy reset so receipts, credentials, selection, cache, and support data leave with it. Two doors, two labels: one cleans the room; the other hands back the keys.

AuraPlay errors got a front-desk translator too. Logs can still keep the crunchy provider and database details engineers need, but visible playlist, search, library, artwork, and playback messages now pass through `AuraPlayErrorPresentation`. Users get recovery copy instead of a framework muttering `localizedDescription` through the UI.

The schema story finally stopped being a shrug. AuraPlay now opens through a real `AuraPlayMigrationPlan`, with V1 modeling the pre-cache/loudness media shape and V2 representing the current store. The migration test seeds old media, playback, and playlist rows, then opens them through the current container and checks the new defaults. That is the persistence equivalent of reheating yesterday's soup before serving it: if the old pot cracks, you find out in CI, not on a user's phone.

## WalletConnectorKit: Maps Are Not Engines

The wallet connector docs had a loud warning hiding in plain sight: Reown and WalletConnect are references, not production dependencies. The code had drifted the other way, adding a Reown AppKit coordinator, a SwiftUI package panel, host-app configuration validation, and a `reown-swift` package dependency before the app had actually integrated wallet connection. It made the demo path look busy, but it pulled SDK assumptions into the package that was supposed to protect the app from exactly that.

The fix put the package back where the plans said it should be. `WalletConnectorKit` now owns the clean-room vocabulary: Phase 4 wallet catalog, CAIP parsing, namespace proposals, WalletConnect URI formatting and nested deep-link encoding, return URL classification, typed wallet errors, request builders, session-store contracts, and a dApp connector that talks only through injected transport and URL-opening boundaries. The app can still build a wallet picker later, but it will be a customer of the kit instead of the place where wallet rules secretly live.

The lesson: a reference implementation is like a restaurant review. It tells you what the meal should taste like; it is not the recipe you paste into your kitchen.

### Follow-Up: The Reservation Book Gets Rules

The next wallet pass moved from labels to lifecycle. A wallet connector that can parse a CAIP account is useful, but it is still just reading the name on the ticket. The app also needs to know what happens after a wallet approves, what survives a relaunch, and what gets cleaned up when a user disconnects.

`WalletConnectorKit` now has those rules without swallowing app infrastructure. Settled sessions can be reduced to deduplicated wallet addresses, session topics can be stored behind a Keychain-backed contract with device-only, non-synchronizing attributes, active wallet selection has a tiny store boundary, and `WalletConnectionLifecycleService` coordinates approve, restore, expire, and remove flows through injected persistence and cleanup adapters. The package still does not know about SwiftData, ENS, Spotlight, or UIKit. It just hands the host app the clipboard and says, "Here is what must be written down."

The small gotcha was Solana. The old code used a long chain reference while the Phase 4 ticket text expected `solana:mainnet`. That kind of mismatch is one character away from "why does this wallet not show up?" The fix normalized the package to the ticket contract and pinned it in tests.

## AuraPlay Privacy Reset: Sweep The Crumbs Under The Toaster

The Phase 14 audit found a privacy reset bug with the personality of a loose floorboard. The reset looked like it was deleting the AuraPlay store, but SQLite keeps two sidecar files beside the main store: `-wal` and `-shm`. The code was looking for `.wal` and `.shm` instead. Close enough for a tired human eye, completely different filenames to a filesystem.

The live SwiftData reset had the same shape of problem at the model layer. It cleared `AuraPlayMediaItem`, which is the big visible shelf, but left the smaller drawers alone: tokens, embeddings, playback positions, tombstones, playlists, and playlist items. A privacy reset cannot just clean the display case while leaving receipts in the register.

The fix made both brooms honest. File reset now removes the real SQLite sidecars, and the live-container reset deletes every model in the AuraPlay schema in an order that respects playlist relationships. The test now seeds all AuraPlay persisted model types before pressing the reset button. Lesson: when a feature has its own pantry, reset tests should put something on every shelf before proving the pantry is empty.

## AuraPlay Playback: One Queue, One Stage

The latest playback bug was a stagehand problem. The new library rows could hand the orchestrator a perfectly good video item, but the app only built the video stage when someone tapped the toolbar's Video button. Press Play on a video row and the performer arrived before the stage existed. The adapter now opens the video route first, waits briefly for the SwiftUI video surface to register its controls, and only then tells the orchestrator to load the item.

The Now Playing sheet had a similar split-brain. Playback started through the new media-item orchestrator, but Skip Next and the queue sheet were still reading the old audio playlists. That meant a new AuraPlay queue could be playing while the UI stared at an empty old notebook. The public controls now read and mutate the orchestrator queue directly; the old preload helpers can still do narrow audio transition work, but the user-facing contract has one source of truth.

The sync cooldown got its own release lesson. Partial provider failures used to mark progress as error but return as if everything was fine, so `syncAllIfNeeded()` wrote a fresh cooldown timestamp after a failed scope. That is like putting a "closed for cleaning" sign on a door nobody cleaned. Partial failures now throw a typed coordinator error after preserving successful scopes, and failed sync attempts do not poison the retry window.

## The Wallet Audit Log Retires Into the QA Plan

WalletConnectorKit had carried a long, append-only `AI-Audit-Log.md` — a multi-model ledger that hardened the SDK-free core over many passes. It had done its job, and its one truth that no desk-bound session could ever close kept repeating: the live vendor wallet clients (Reown, Coinbase, Privy, Dynamic) have never been run against a real wallet on a real device. That is a device-QA fact, so it belongs in the plan a human actually runs on hardware, not buried in a 1,200-line package ledger.

So the log was retired into the docs people open on purpose. Inside the package, the QA checklist absorbed the standing live-wallet ship gate, the known-limitations table, and a verification-status summary. In the app, `P0-Physical-Device-QA-Suite.md` gained `P0-Device-020`, a live-wallet connection pass covering connect/reject/sign/disconnect/restore and ownership verification with the real crypto provider. The lesson mirrors the AuraPlay one: findings should end up either fixed with a guarding test or distilled into the contract docs a maintainer reads, never left to grow in a ledger nobody reopens.

## AuraPlay Audit: The Package Tests Were Holding Receipts

The Phase 14 audit did the thing release audits are supposed to do: it made the quiet corners talk. The Xcode app suite was green, but standalone package tests found stale test contracts and one real metadata blind spot. `audio_url` was common enough provider vocabulary that ignoring it meant some playable NFTs could walk right past AuraPlay wearing the wrong nametag. The metadata updater now accepts the snake-case field and preserves MIME types from ERC-1155 file arrays, even when the IPFS URL has no useful extension.

The test fixtures had their own lesson. A cached image fixture set `originalUrl` but not `secureUrl`, and a persistence merge test created its "existing" NFT under a different account scope than the refresh. That is the test equivalent of checking whether two keys open the same door while standing in two different buildings. The fixtures now model the real scoped identity and secure-image cache contract more honestly.

The remaining smoke alarm turned out to be two alarms sharing one hallway. `AVAudioPlayerNode` can throw an Objective-C exception before Swift has a chance to catch it when the macOS SwiftPM runner lacks the scheduled-player audio unit, so the real-engine tests now check Core Audio component availability before constructing the graph. The cache tests had a different issue: they tried to test eviction with caps below the production minimum, so they now use a test-only unclamped cache manager path while the public settings path still clamps user values. The suite now runs to completion; the skipped real-engine cases move to the device QA contract where actual audio hardware and codecs exist.

## Auralis-Fast: Taking The Training Wheels Off

The Xcode 26 beta runner used to make app-hosted SwiftData tests act like a trapdoor: load the same `@Model` class from the app and test bundles, and some account, receipt, search, privacy, and AuraPlay persistence checks would crash or hang before they could tell us anything useful. Those skips were honest at the time, but by Phase 14 they had become a release-proofing blind spot.

The recheck started ugly: the first direct account-store probe timed out, which looked like the old trapdoor was still there. After isolating the runner and sampling nearby tests, the pattern changed. Pure model presentation checks passed, then SearchHistory, receipts, view services, AuraPlay persistence, music receipt integration, undo, privacy reset, P0201 flows, and finally the direct AccountStore suite all ran cleanly. The lesson is a good beta-era one: do not blindly trust stale skip labels, but also do not delete them on faith. Make each locked door prove it is still locked.

The result is better than "not failing": `Auralis-Fast` now runs 650 app tests with zero skips. That turns the former beta workaround back into a real release gate.

## Mission Control Phase 1: The Control Room Gets Windows

The Phase 1 checklist had a funny problem: the machinery was no longer imaginary, but too much of it was still hiding behind the wall. Runtime primitives existed, receipts were chained, playbooks could run, and operators could produce artifacts, but Mission Control still felt more like a hallway of gauges than the room where an operator could inspect the actual system.

This pass gave the control room windows. Mission Control now opens first, not as a side tab the user may or may not notice. Workflow rows open into session detail, where the worklog shows proposals, checks, judge decisions, execution, and failures. Approval items now have a proposal preview with a before/after risk view, which is the governance version of looking at a transaction simulation before signing it.

The context bundle also stopped being just a type in `RuntimeCore`. Mission Control now shows the live bundle fields, their sources, freshness, data classes, and contract validation. Artifacts gained the other half of their job too: export with provenance metadata and compare version history. The best lesson here is simple: a kernel earns trust when its boundaries are inspectable. A locked door is not enough; the user needs to see the lock, the key, and the receipt for who used it.
- Capability-firewall and package-boundary cleanup:
  The architecture had one cardboard storefront left on the block: `AgentIdentityCore` exported an empty enum while still ordering the heavyweight ENS/secp256k1 delivery truck. Since `ActorRef` already has a real home in `RuntimeCore`, the placeholder package and its unused dependency graph were removed. The adversarial suite now also starts one layer earlier with a deliberately malicious `GoalPlanning` double. It receives an innocent wallet-summary request, tries to smuggle in a `signMessage` execution step, and proves the real authorization ladder stops it before the executor moves. The lesson is pleasantly blunt: a planner writes suggestions, not permission slips.

## Receipt Signing Learns to Fail Closed

The receipt chain already had the right cryptographic furniture: chained hashes, monotonic account sequences, P-256 signatures, protected heads, and exportable verification material. One small trapdoor remained under the signing desk, though. A signing error was swallowed with `try?`, which meant a new receipt could still be persisted without the signature that gives its provenance teeth.

That path now fails closed. If the signer cannot establish provenance, the append aborts before SwiftData sees a row. Historical unsigned receipts remain readable so migrations do not rewrite history, but the rule for new ledger entries is crisp: no signature, no receipt. A deliberately failing signer now guards the boundary in tests. The memorable version is the nightclub rule—legacy guests already inside can be escorted out safely, but nobody new gets through without a stamped wristband.
## 2026-09-01 — Waiting for the bell instead of staring at the clock

The social relay composition test had a classic concurrency gremlin: after feeding a sealed inbound message to the pump, it repeatedly peeked at the event store for roughly one second and hoped the pump had finished. Usually it had; under a busy full-suite run, sometimes it had not. That made a healthy relay look broken.

The test now waits on the composition layer's real `onInboundProcessed` seam using a one-shot actor signal. Think of it like waiting for the kitchen bell instead of checking the pass every five milliseconds. Both the accepted-message and foreign-key rejection paths now observe the exact processing boundary, without sleeps or inflated timeouts. The receipt-hardening plan was also corrected: production already selects the Secure Enclave signer on supported hardware and falls back to persistent software P-256 where the Enclave is unavailable; the remaining task is physical-device verification, not implementation.

The full plan found the same species of gremlin in AuraPlay's cadence persistence test. Its ten-millisecond production timer was being used as a test clock, which is like testing an alarm clock by waiting beside it with a stopwatch while the entire test suite moves furniture around the room. `PlaybackOrchestrator` now accepts an injected asynchronous cadence wait while preserving its five-second production default. The test advances a manual cadence actor and awaits the exact store write, so it proves periodic persistence without depending on scheduler speed.
## 2026-09-01 — The Wallet Observer That Refused To Leave The Party

The full test host once trapped inside a SwiftData fetch while wallet-session tests were running. The predicate was innocent; the awkward guest was an unstructured connector-event task that the service started but never owned. Tests could finish and release their in-memory model containers while those observers were still alive, and parallel wallet scenarios widened that teardown window.

The service now keeps the task handle, cancels any prior observer before starting another, checks cancellation while consuming the stream, and cancels the observer during deinitialization. The wallet interaction suite is also serialized: those tests deliberately model one app-lifetime wallet connector and one main SwiftData context, so pretending ten such app lifetimes should overlap was unrealistic stress, not useful parallelism. The memorable rule is simple: if you start the band, keep the drummer's phone number so you can tell them when the gig is over.

## 2026-09-01 — The Receipt Export Gets a Passport

The local receipt ledger already had locks on the filing cabinet, but its export was still a stack of photocopies. Every receipt carried a signature, yet the exported JSON had no signed cover sheet saying how many pages belonged in the stack, which chain heads were authoritative, or which device identity vouched for the bundle. Worse, integrity verification treated a missing signature like an old guest without a name badge: it simply walked past the check.

Verification now fails closed whenever either half of the signing metadata is absent. Export also produces a versioned provenance envelope with a canonical record hash, per-account protected heads, a P-256-signed manifest, and the signing key's SHA-256 fingerprint. The independent verifier rebuilds every payload hash and chain link, verifies every receipt signature, checks the manifest and heads, and requires the caller to supply the expected fingerprint from a separate trusted channel. That last detail matters: printing “trust me” on your own passport does not make it government-issued.

The engineering lesson is that integrity and provenance are cousins, not twins. A self-consistent file proves nobody changed it after its signer assembled it. A pinned fingerprint proves which signer assembled it. Ship-grade exports need both.
# The Signing Desk Stops Making Spare Keys

The receipt ledger already behaved like a meticulous hotel register: every page pointed back to the page before it, and the latest page number lived in a separate Keychain safe. But the signing desk had one alarming habit. If the safe was locked, unavailable, or returned damaged key material, it could quietly cut a fresh key and carry on. The new signatures were mathematically valid, but the hotel's identity had changed without an alarm. That is exactly the sort of “helpful recovery” security code must never attempt.

Receipt signing now crosses an async actor boundary. Keychain reads and add-or-update writes happen serially, every `OSStatus` becomes an explicit error, corrupt stored keys are rejected, and a receipt append fails before persistence if the existing signing identity cannot be restored. Four injected-store tests exercise stable restoration, locked-Keychain failure, save failure, and corrupt material without making the test suite rummage through a real user's Keychain.

We also gave provenance a proper introduction ritual. `provenanceTrustAnchor()` exposes the signing fingerprint separately so an auditor can pin it *before* receiving an export. Reading the fingerprint from the document you are trying to authenticate is like asking a stranger to print their own passport at the door: internally consistent, perhaps, but not independently trusted.

Finally, the architectural fences acquired wider tripwires. The test suite now checks the entire first-party Swift package graph for cycles and empty identity stubs, app code is forbidden from invoking tool executors around the governed runtime, and CI directly runs ReceiptStorage, RuntimeCore, and PolicyCore package suites. Execution isolation here deliberately means an in-process capability firewall—not a sandbox for hostile native binaries. If native plugins ever become untrusted code, that is the moment to build an XPC blast door, not rename an actor and hope for the best.

## The Passport Photo Must Match the Passport

The provenance export had one final identity loophole hiding behind perfectly valid cryptography. Each receipt verified its signature against the public key stored beside that signature, while the manifest verified against the separately pinned device key. An attacker who could edit the database could replace both a receipt signature and its neighboring public key with a fresh, valid pair. The chain contents and signed manifest still prevented rewriting history, but local verification would incorrectly accept the receipt's replacement autograph before export.

Receipt signing now exposes its stable public identity directly. Local integrity checks require every receipt signer key to equal that identity, and external export verification requires every receipt key to equal the pinned manifest key. The adversarial tests deliberately generate a second P-256 signer, sign the authentic chain hash, swap both fields, and prove that mathematically valid forgery is still the wrong identity. Think of it as airport security finally checking that the passport photo belongs to the person holding the passport, not merely that both are high-quality prints.

The architecture fence also learned direction, not just geometry. An acyclic package graph can still point a basement utility toward a rooftop feature, so ADR-008's layers are now executable test data: dependencies may point sideways or downward, never upward. The retired `AgentIdentityCore` manifest is explicitly forbidden from returning, and the malicious-planner suite now runs in CI alongside the runtime firewall. The lesson is that a boundary written only in prose is a polite request; a boundary represented in tests is a locked gate.

## 2026-09-02 — The Release Train Names Its Track

The hardening code was in better shape than its release proof. CI ran the app's tests through the
`Auralis` scheme, but it did not name a test plan, leaving the selected plan as invisible state. That
is like announcing that a train reached the station without recording which track it used. CI now
selects `Auralis-Full` explicitly; `Auralis-Fast` remains useful for short feedback loops, but it can no
longer masquerade as the complete release matrix.

ADR-008 also puts a bright label on the runtime's lock. `RuntimeHost` and `GovernedToolPipeline` form
a real capability firewall for trusted code sharing the app process. They are not a concrete bunker
for hostile native binaries. If Auralis later admits untrusted native plugins, those executors need an
XPC or Enhanced Security extension blast door, narrow value messages, and hostile-input validation on
the way back. The lesson: a strong lock is safest when the blueprint says exactly which door it guards.
# The Governed Tool Pipeline Grew Real Hooks

The runtime used to have “before” and “after” stages written on the kitchen wall, but they were still
part of one large recipe. We turned those stages into actual contracts: `BeforeToolCallHook` owns schema
validation, deterministic checks, and judging; `AfterToolCallHook` receives an immutable terminal result
only after the mandatory audit trail is emitted. Additive hooks cannot erase receipts, worklog entries,
artifact links, or performance signals.

One useful war story: the registry previously behaved like a hotel that quietly handed the same room key
to a second guest. Duplicate IDs could replace a tool definition during bootstrap. Registration is now
idempotent for the exact same definition and rejects conflicting definitions without replacing the first.
The pipeline also verifies that an executor's artifact names the tool actually executed, preventing a
miswired executor from attaching evidence to the wrong governed action.

The second hardening pass closed a subtler loophole: an executor protocol is still a public doorway
when any caller can manufacture every argument. Tool execution now requires a
`ToolExecutionAuthorization`, whose initializer lives inside RuntimeCore. Think of it as the kitchen's
order ticket: outside code may implement a station, but only the governed expediter can stamp a ticket
after registry resolution, checks, policy, and approval have succeeded.

The standard after-call hook also became the single owner of receipts, worklog execution events,
artifact-link events, and performance signals. Those sinks are non-optional, and custom observers run
only after the mandatory trail is written. Bootstrap now treats conflicting tool IDs as a programming
error instead of shrugging and continuing with whichever definition happened to register first.

The final boundary pass locked the control room itself. Pipeline construction and registry mutation are
now `RuntimeComposition` SPI, imported only by the trusted RuntimeKit/OperatorsFeature composition seam.
Mission Control receives a read-only tool catalog from `RuntimeHost`; it no longer reaches into the live
registry. RuntimeKit also has exactly one pipeline factory and always installs `DomainJudge`, so there is
no production side door for swapping in an “everything is fine” judge. An architecture test patrols the
app target for pipeline construction, registry construction, SPI imports, or authorization forgery.

## Evidence Is Part of the Outcome

The last pipeline audit found a dangerous little lie: a tool could finish, the session could announce
“completed,” and only afterward could its required receipt fail. That is like a restaurant declaring
the till balanced before printing the transaction record. Terminal events now come last, after the
mandatory after-hook has attempted every evidence sink.

Evidence failures also retain the underlying truth. `evidenceIncomplete` says both what happened
(executed, blocked, revised, failed, or awaiting approval) and which evidence writes failed. Before-call
receipt failures are no longer swallowed, and after-call hooks collect every failure instead of stopping
at the first broken observer. Approval resumes similarly carry the original escalation context: a fresh
or changed approval prompt cannot hitch a ride on an older consent.

Finally, standing Observe/Assist/Operate policy moved into PolicyCore as one side-effect-free rulebook.
The judge now judges contextual/check evidence; it no longer keeps a second, subtly divergent copy of
the mode policy. One rulebook, one answer, fewer haunted hallways.

## 2026-09-03 — Closing the Gap Between the Replay and the Radio

Mission Control used to start two independent jobs when its screen appeared: one replayed stored
events while the other tuned into the live event stream. Usually that worked, but there was a tiny
hallway between them where an event could run past after replay finished and before the radio was on.
The screen now subscribes first, then hydrates history while the bounded stream buffers new arrivals,
and finally drains the buffer with event-ID de-duplication. The handoff is now one continuous timeline.

The receipt observer also stopped swallowing a broken persistence write. It records a failure count and
the responsible event ID and emits a privacy-safe system log, giving diagnostics something concrete to
inspect without leaking provider details. Finally, both in-memory and SwiftData event history treat
zero or negative limits as an empty request instead of handing an invalid value to collection or fetch
APIs. Boundary inputs are like coat-check tickets: validate them at the counter, not after somebody has
already disappeared into the back room.

## 2026-09-04 — The Context Guest List Gets a Bouncer

The first context contract could check whether expected guests arrived with the right badge, but it
never checked the rest of the room. An undeclared sensitive field could stroll in beside a valid wallet
field, pass validation, and reach the operator. Duplicate names were sneakier: validation inspected the
first field while dictionary conversion kept the last. The clipboard and the person entering the room
could disagree.

Context validation now creates an approved projection instead of merely issuing a thumbs-up. Unknown
fields are rejected by default or explicitly omitted, duplicate keys fail, invalid contract shapes fail,
and timestamps too far in the future are not mistaken for exceptionally fresh data. Missing/stale policy
can be declared per field, and bundles plus contracts are versioned Codable values with tolerant legacy
decoding. Most importantly, a missing workflow contract blocks execution, and the operator receives only
the approved projection—not the provider's original bag of data.

Every built-in playbook now has its own named contract, even while their small default operators consume
the same definition fields. That distinction matters: adding holdings, memory, plugin output, or preferences
now requires changing the corresponding guest list first. Adversarial tests cover undeclared secrets,
duplicate-key smuggling, projection filtering, clock skew, serialization, and absent contracts. The lesson
is simple: governance is not a sign saying “authorized people only”; it is the person at the door checking
the list and handing each guest exactly the badge they are allowed to wear.

## 2026-09-04 — The Bouncer Stops Lending Out the Stamp

The guest list still had two trust gaps. First, any neighboring package could manufacture the
`GovernedContext` stamp that was meant to prove the bouncer had checked the list. Second, the audit
fingerprint described each guest's badge, source, and arrival time without committing to who the guest
actually was. Two different wallet values could leave the same evidence. That is a beautifully printed
coat-check ticket with no coat number on it.

`GovernedContext` is now a capability rather than a decorative wrapper: only RuntimeCore's governance
boundary can construct it, and it is no longer decodable from an untrusted blob. Provider-routed model
requests must cross the same authorization factory used by scheduled work, with explicit contracts for
planning, autopilot steps, operator inference, and search. An architecture patrol rejects future direct
construction or raw model-context dictionaries outside the kernel.

Evidence now includes a SHA-256 commitment to each canonical value. Audit output still reveals no wallet,
query, preference, or vault handle, but changing any approved value changes the digest. Contract registries
also validate declarations on entry: empty IDs, invalid schema versions, duplicate workflow IDs, duplicate
requirements, negative freshness bounds, and negative clock skew fail closed as typed configuration errors
instead of waiting for a live run—or crashing inside `Dictionary(uniqueKeysWithValues:)`.

The memorable rule is: a proof token must be harder to forge than the fact it claims to prove. If anyone
can stamp the ticket, or if the ticket is not bound to the checked data, governance is only typography.

## 2026-09-04 — The Prompt Finally Uses the Front Door

The bouncer was real, but three regulars still knew about the kitchen entrance. On-device planning,
autopilot steps, and assistant search created `LanguageModelSession` directly. Their remote twins showed
their context badges at the door, while local inference walked goals, rationales, wallet scope, and search
queries straight into the prompt. “It stays on this device” is a privacy advantage, not a permission slip
to skip data governance.

Local and remote inference now share the same authorized-request builders. Dynamic prompt material is
classified—including a distinct `userProvided` class—tagged with a closed authoritative source, checked
for freshness, and then rendered only from `GovernedContext`'s approved projection. The request factory
accepts a prompt-building closure after validation, which turns the safe projection into the only pantry
the prompt chef can reach. Runtime capability catalogs also moved out of the higher-priority instruction
channel and into that governed projection.

Workflows now carry their contracts as part of the persisted `Playbook` value. New playbooks cannot be
constructed without one; older stored playbooks decode with a narrow, reject-extra compatibility contract.
Likewise, every field requirement must explicitly state freshness, source, and missing-field behavior—even
when the deliberate answer is “unbounded” or “no authoritative source.” The compiler is now the clipboard:
forgetting a policy choice is a build error, not a future privacy surprise.

One useful war story surfaced immediately. Mission Control had been labeling an artifact's creation date
as the context field's refresh date. Once freshness became mandatory, an old artifact made a freshly read
snapshot look stale. The fix was conceptual, not cosmetic: object age and observation freshness are
different clocks. Context fields now record when the inspector refreshed the source, while domain models
retain when the underlying event or artifact was created.

## 2026-09-04 — The Approval Button Learns “Once”

The trusted UI registry originally looked like a guarded service counter, but several production screens
were still serving the same goods from side doors. Receipts, capability leases, and context fields now
enter through `TrustedUISurface`, and the user-playbook editor exercises the governed draft request
instead of maintaining an unrelated editing path. An architecture test patrols the boundary: operator,
autopilot, and playbook packages may describe UI requests, but importing SwiftUI, UIKit, or AppKit there
is now a build-breaking offense.

The nastiest bug was a classic double-tap race. The approval screen launched asynchronous work but left
its buttons live, so a quick thumb could ring the execution bell twice. The view now claims a one-shot
latch synchronously, disables every decision button, and shows a submitted state. Mission Control also
claims the approval ID before its first suspension point, providing a second lock if a stale view or a
second presenter reaches the model. Trust boundaries should wear both a belt and suspenders.

Large text also stopped being an afterthought. Approval details and controls use `ViewThatFits` to move
from rows to readable stacks, buttons retain full touch height, and the primary trusted controls have
stable identifiers mirrored in the central accessibility registry. Resolver and action tests now prove
that missing drafts/receipts fail closed and that callbacks fire only when the schema permits them.
# Worklogs That Admit When They Drop the Clipboard

The worklog used to behave like a court stenographer who quietly went home whenever the database
misbehaved: execution continued, but nobody was told that part of the transcript was missing. The
storage boundary now returns a typed `WorklogRecordResult`, tracks `WorklogStoreHealth`, rolls back a
failed SwiftData save, and lets Mission Control say plainly that a trace is incomplete. High-risk
actions fail closed when even their opening proposal cannot be durably recorded; lower-impact work
may continue, but the degraded audit state remains visible. Execution durations are also validated,
because `NaN` is a perfectly legal `Double` and a perfectly terrible JSON audit record.

## The Worklog Learns to Raise Its Hand (September 2026)

Receipts remain the restaurant bill: concise, durable, and understandable. The worklog is now the
kitchen ticket rail, and importantly, a dropped ticket no longer fails silently. Every runtime-owned
writer goes through an evidence-reporting recorder; failures appear on the runtime event stream, and
scheduled execution records carry an explicit `EvidenceCompleteness` result. High-risk governed work
already fails closed when its first mandatory worklog entry cannot persist, while post-execution
evidence failures become an `evidenceIncomplete` outcome instead of a suspiciously clean success.

The eval layer now photographs the evidence it graded. An `EvalResult` stores its owning playbook and
a compact trace-health snapshot, so pruning an execution record cannot orphan a grade and an
inconclusive report card can explain whether the trace was empty, degraded, non-terminal, or contained
unknown future events.

Adaptive improvement is deliberately a suggestion box, not a self-modifying robot. A pure engine
turns repeated failures, criterion misses, latency shortfalls, and unhealthy traces into deterministic,
evidence-linked recommendations. Mission Control lets a person accept, reject, or mark an accepted
recommendation applied. Those transitions are persisted and themselves produce a worklog entry and
receipt, but they cannot edit a playbook, grant a capability, or widen policy. The memorable rule is:
the report card may recommend a sharper knife; it never gets to hand itself one.

One migration lesson: adding a SwiftData model to the operator-runtime container is safer when the
payload remains independently Codable. The indexed columns support sorting and lookup, while the blob
preserves the domain contract and keeps future lifecycle additions tolerant.

## The Roadmap Learns the Difference Between a Seedling and a Tree (September 2026)

The Phase 1 documents had drifted into an awkward contradiction: one page said autopilot did not exist,
while another accurately described a user-triggered governed runner doing real work. Both were trying to
protect the same boundary, but they confused “some machinery exists” with “the production capability has
shipped.” We reconciled the roadmap around three honest labels: absent, foundation/POC, and production
deferred.

That vocabulary matters most around authority. The current autopilot is an explicit, user-triggered POC
that still passes through policy and receipt gates; it is not unattended autonomy. EvalCore's current
recommendation lifecycle is a suggestion box, not full outcome evaluation or a self-improvement loop.
Social sessions are coordination scaffolding, not autonomous multi-agent orchestration. The map now also
names advanced memory graphs explicitly as deferred instead of leaving them in a foggy “maybe later”
corner. A sapling can be real without pretending it is already a forest.

## The Alarm Clock Stops Hitting Snooze Forever (September 2026)

The first event scheduler carried only a Boolean: somewhere, something was stale. That is like an alarm
clock remembering that it rang but forgetting which morning it was. Every background scan could treat the
same old condition as brand-new work. Event signals now carry the moment a condition became actionable,
and the scheduler compares that moment with the routine's last run. One event produces one run; a genuinely
new event can ring the bell again.

Approval aging also moved back to the source of truth. An old worklog escalation is history, not proof that
approval authority is still pending. The process-local approval registry now timestamps requests and removes
them from age queries when consumed. That preserves the fail-closed rule—approval authority still evaporates
on relaunch—while stopping completed approvals from haunting the scheduler like paperwork-shaped ghosts.

Mission Control now turns raw counters into a deliberately conservative trust label. Fewer than five runs is
“Not enough data,” because one lucky success does not make a routine stable. After that, recurring failures and
failure/block rates distinguish Stable, Needs Attention, and Flaky. These labels are dashboard instruments,
not accelerator pedals: no metric can grant a lease or widen authority. Installed routines with no history are
shown instead of disappearing, approval rate is visible, and every status has text and an icon so color is never
the only messenger.
### The dashboard that hid the bouncer

The performance dashboard used to call one section “Failure history” while quietly showing only
operator execution errors. Policy and authority blocks still affected a playbook’s health score, but
the supporting rows vanished from the history—as if a restaurant’s scorecard counted every guest
turned away while the incident log recorded only dropped plates. The history now includes both
`.failed` and `.blocked` executions, so a flaky classification and its inspectable evidence tell the
same story. A focused regression test keeps successful runs out while retaining both unsuccessful
outcomes.

### Two dialects for “artifact produced”

The evaluator originally understood artifacts only when a governed tool wrote an `.executed` event.
Scheduled routines speak a slightly different trace dialect: they write an `.artifactProduced`
routine phase. The artifact was safely stored, yet evaluation looked at the paper trail and concluded
that nothing had been produced—like rejecting a delivery because one courier stamped “delivered” and
another stamped “parcel received.” The `producedArtifact` criterion now recognizes both canonical
forms, with a direct evaluator test and an end-to-end RuntimeHost test proving the resulting next
action is complete. Compiling the package suites also caught stale test fixtures after receipt and
playbook storage APIs became stricter; those fixtures now provide explicit attribution and propagate
persistence errors instead of relying on obsolete signatures.
## 2026-09-06 — The Bouncer Learned to Check the Whole Passport

The first narrow operators were already wearing governance badges, but two scope checks were still
more like glancing at a name tag than checking a passport. On-Chain Watch matched an address without
its chain, and Identity Review searched free-form receipt text for whatever identity somebody typed.
That could mix the same hexadecimal address across networks or mistake a mention of another account
for ownership.

The boundary now uses structured coordinates. Watch observations must match both chain and address;
identity observations must carry an exact structured identity/account value; and RuntimeHost refuses
an identity review unless its scope equals the shell's active identity. Because RuntimeHost is reused
across tabs, account switches explicitly refresh that identity boundary—the security equivalent of
updating the guest list when the evening shift arrives.

Research Brief now requires a real, non-blank query. Mission Control shows the fixed active identity
instead of offering an arbitrary identity field, and a watch finding flows into the distinct
confirm-first prepared-action route. The important model remains deliberately boring: observing is
read-only, preparing is separately governed, and signing or broadcasting never sneaks into either.

The tests now cover blank research rejection, cross-identity refusal, structured identity filtering,
and chain-qualified watch matching. The operator UI test no longer treats a missing runnable operator
or artifact as a reason to skip the proof.

## 2026-09-06 — The Watch Operator Stopped Borrowing Someone Else’s Wallet

The original On-Chain Watch demo arrived with a famous Ethereum address already in its pocket. Handy
for a screenshot, awkward for a production operator: pressing Run could inspect a target the active
identity never chose. The sample is gone. A watch now needs an explicit chain-qualified address and
fails closed without one, like a courier refusing to leave until the parcel has both a street and a
city.

The production assembly now gives the operator a narrow adapter that combines two evidence streams:
local receipt history and a read-only native-balance snapshot from the configured provider. It can
observe and prepare a confirm-first review packet, but it has no signing or broadcast capability.
Provider failures become sanitized observations, so operational detail does not leak into artifacts.

Identity Review also learned to sort its desk properly. Successful records are changes; recent
failures are anomalies; old unresolved failures are stale tasks. Those buckets are disjoint, avoiding
the old double-count where one dusty failure could wear two labels.

The best war story came from finally making the simulator proof strict. Once the UI test stopped
skipping unreachable controls, it found a genuine runtime defect: the Research Brief executor emitted
`sourceReceiptCount`, while its declared output schema rejected that very field. The operator could
compose an artifact and then be bounced by its own contract—the software equivalent of printing a
boarding pass that your own gate scanner cannot read. The schema now describes the complete output,
and stable identifiers cover the compact section picker, operator outcomes, and artifact rows.

## 2026-09-07 — Mission Control Got a Preflight Checklist

A production review found three quiet-failure traps hiding behind an otherwise healthy console. The
package tests existed but had no durable package scheme, automation identifiers had grown a second
registry, and a damaged watchlist looked exactly like a user who had never configured one. Those are
all versions of the same engineering smell: evidence existed, but the path to that evidence was
ambiguous.

Mission Control now points at AuraUI's single accessibility-ID registry, its snapshot baselines and
lockfile are source-controlled, and watchlist persistence throws typed failures. The model treats a
failed save like a bank transfer that did not clear: it restores the prior visible balance and raises
a data-quality warning instead of pretending success. Console-only derivations also moved into a
focused extension, beginning the job of turning the oversized home model from a crowded junk drawer
into labeled cabinets.

## 2026-09-12 — The Black Box Stopped Eating Damaged Evidence

Two storage edges had optimistic stories that did not survive a bad day. A malformed social snapshot
was translated into “nothing here,” and live runtime events arriving while audit history replayed sat
in an unlimited waiting room. The first could erase an outbound queue on the next save; the second
could trade a slow disk for runaway memory.

Social persistence now treats unreadable bytes like evidence at an accident scene: it preserves the
original, makes a quarantine copy, exposes the degraded state, and refuses to paint over it until a
caller explicitly chooses to discard it. The runtime event bus now gives its replay-side waiting room
the same capacity as its live stream. Overflow closes the subscription and lets the reliable consumer
reconnect from its durable checkpoint—the audit equivalent of reopening the ledger instead of piling
paper to the ceiling. Corruption tests cover all three social stores, and an actor-reentrancy test
holds history loading open while publishers deliberately overflow the replay buffer.

## 2026-09-12 — The Observers Learned to Reserve Their Seats

The runtime's receipt and performance observers had an actor-reentrancy trap in `start()`. Each
observer checked whether a consumer existed, then suspended while registering its event stream. Two
callers could both pass that check before either returned—like two ushers seeing the same empty seat
and issuing separate tickets. The duplicate consumers could race checkpoint updates and process the
same reliable event more than once. A stop during that suspension was worse: the old start could wake
later and install an orphan consumer after shutdown.

Startup now reserves one shared registration task before its first suspension and tags it with a
lifecycle generation. Concurrent starts await the same reservation; `stop()` cancels it and advances
the generation, so stale work cannot reattach. Consumer loops also check cancellation before writing
checkpoints or reconnecting. Focused tests hold registration open on purpose and prove both concurrent
startup and stop-then-restart behavior. The release gate also exposed test fixtures still using the
pre-grouped `RuntimeHost` initializer; they now compose stores, governance, models, operators, and
identity hooks through the production API. RuntimeKit's complete 198-test suite passes.

## 2026-09-12 — Time Travel and Déjà Vu

Two small clocks were telling different stories. The capability registry accepted an `at` timestamp
for deterministic expiry sweeps, but its first durable read quietly compared leases with the real
wall clock. Asking “what was expired at noon?” could therefore get an answer influenced by dinner.
Hydration now uses the caller's sweep instant, preserving both restart deduplication and honest
historical evaluation.

The performance observer had a different time-loop problem. Checkpoint writes are intentionally
coalesced, so a crash may replay a short tail of runtime events. Receipt processing already recognizes
that déjà vu, but planner metrics did not: the same completed run could be counted twice after
relaunch. Planner performance records now inherit the terminal runtime event's UUID, and a new
observer rebuilds its deduplication set from durable performance history before subscribing. The
lesson is pleasantly blunt: if replay is part of the reliability design, idempotency must survive the
process—not merely the task that happened to be running.
# Receipt Recovery and Honest Waiting States

Three tiny-looking `try?`/state-mapping choices turned out to be the software equivalent of a smoke
alarm with the batteries removed. Artifact lookup now distinguishes “missing” from “stored but
corrupt,” and receipt compensation reports the especially dangerous case where both the primary
Keychain update and the database rollback fail. Recovery code is part of the integrity boundary; it
cannot quietly shrug.

Scheduled routines also gained an explicit `awaitingApproval` worklog phase. Previously, a prepared
run needing a human decision wore a “Completed” badge, like a restaurant marking dinner served while
the order was still waiting at the pass. The trace, Mission Control projection, evaluation, and
retention logic can now agree that waiting is neither failure nor completion.

## 2026-09-12 — Persistence Must Leave a Footprint

Several operator-runtime stores used `try?` around SwiftData encoding, lookup, and save operations.
That kept the runtime moving, but it also made a failed authority or evaluation write vanish without
even a diagnostic—the database equivalent of a courier losing a package and marking the delivery
complete. These paths now report the failed operation through structured logging and roll their model
context back, so an unsuccessful save cannot leak dirty mutations into a later, unrelated save.

Artifact versioning received the same transactional seatbelt. Superseding the old versions and saving
the new one form a single logical move; if any part throws, the context rolls back rather than leaving
the previous artifact wearing a premature “superseded” badge. The retired `AgentIdentityCore` package
also lost its final tracked journal and resolution file. Its useful identity responsibilities already
live in `RuntimeCore` and `ENS`, while an architecture test keeps the empty package from quietly
returning.

## 2026-10-20 — The Lock That Cried Wolf

An NFT refresh crashed on an assertion inside the receipt ledger. The thread was a Core Data queue
and a runtime-session write was in flight on another, so the report looked like a SwiftData
threading violation — but the receipt store has owned a dedicated `ModelActor` context all along,
and neither of those facts could set the thing that actually tripped. What tripped was the ledger's
own non-reentrant lock: `assert(!LedgerLock.isHeld)`, firing because the task tree appending
`nft.refresh.started` was already carrying the lock's task-local marker.

The assertion had been written as a kindness. Re-entering the ledger lock means waiting on yourself,
and a hang is the worst thing to receive a field report about, so the marker existed to turn a
silent deadlock into a loud programming error that debug builds would catch before shipping. The
crash was that kindness arriving at the wrong moment: a trap in front of a person, over a telemetry
write whose own recorder already treats failure as best-effort and carries on. Worse, `assert`
meant the two build configurations disagreed about what the rule even was — a crash in debug, the
original self-wait in release. A rule with two consequences is two rules.

So the refusal is now a thrown error, identical in both configurations. The more interesting half of
the fix is that the condition had to get *narrower* at the same time. A single process-wide boolean
cannot mean "this lock is held by me" when the store is memoized per `ModelContainer` and task-locals
are inherited by every unstructured task spawned beneath a locked body. One store's body spoke for
every other store's queue, and the marker outlived the body that set it, travelling into whatever a
`modelContext.save()` notification happened to wake. Those are not re-entrancy; those tasks queue
behind the tail like any other caller and complete. Throwing on the bare boolean would have traded a
rare hang for a steady drip of discarded receipts.

The marker now names its store, its acquisition, and the operation holding it, and the ledger tracks
which acquisitions are still live. A refusal requires all three to line up: same store, still
running, genuinely nested. Everything else proceeds, and logs a line saying where it inherited the
marker from — because the escape route is still unidentified, and the next occurrence should name
itself rather than be guessed at. The lesson is an old one wearing new clothes: a safety check is
only as honest as the thing it actually measures, and "a flag is set somewhere in my task tree" was
never the same proposition as "I am about to wait on myself".

## 2026-10-21 — The Accessibility Whack-a-Mole

Seven accessibility audits had been failing for so long that the report described them as one
problem. They were closer to a row of dominoes: repairing a zero-width badge exposed the next
Dynamic Type warning, and fixing that revealed a fourteen-point-tall button underneath it. The
useful lesson was to keep rerunning the exact screens instead of treating the first reported element
as the whole defect.

The real fixes now live in the shared primitives: section headers protect trailing badges from being
compressed to nothing, feedback text and buttons grow vertically, action rows fall back to a stack,
and receipt outcome cards adapt when a pill no longer fits beside their explanation. The Home
receipt link gained a genuine 44-point target, while shortened wallet addresses expose a readable
label and the complete address as their accessibility value. A few XCTest reports remained for
native controls and text already using semantic styles; those exceptions are matched by exact labels
rather than brittle hierarchy dumps.

This is not finished. Re-running `AccessibilityAuditUITests` on the iPhone 16 (26.0) simulator after
the fixes left the receipt-detail and receipts-list audits still failing — the first on a clipped
`AuraPill` title, which is why the pill dropped its two-line cap, and the second on a Dynamic Type
report for a pill the suppression list already names by label, which is its own puzzle. Progress
against the former baseline is real, but "the failing audits now pass" would be a claim the run does
not support. The broader lesson still sticks: an accessibility test exception should be a scalpel
with evidence, never a blanket — and the evidence has to be a run, not an expectation.

## 2026-10-21 — Receipts Followed the Real Playlist Home

AuraPlay had two playlist roads: the current SwiftData service and an older app-owned path. Receipts
were standing beside the older road counting traffic, so the audit trail looked complete while the
shipping UI could drive past unseen. The fix was a decorator around the current playlist manager.
It compares before and after snapshots, emits create/modify/delete receipts for real changes, and
stays quiet for no-ops. That last detail matters: an audit log that records imaginary changes is a
smoke alarm that chirps whenever someone walks through the kitchen.

The same cleanup principle now applies to semantic search. Removing media also removes its embedding
in the same persistence transaction, preventing invisible derived data from outliving its source.
Gateway overrides and recovery copy also gained typed, tested boundaries. The package's 132 tests
passed together, which is the useful kind of confidence here: not merely that each new cog turns,
but that the whole music machine still plays after installing them.

## 2026-10-21 — The Plans Finally Became History

The last AuraPlay gap list had become a peculiar museum: some exhibits were already shipping, some
were deliberate constraints, and a few were genuine future ideas. We closed the code contracts first
— receipt-backed active playlists, duplicate-safe playback receipts, derived-data cleanup, privacy
purge, metadata overlays, deterministic semantic fixtures, and a preview-only auto-organizer — then
ran the MusicFeature package's 132 tests and the focused app-hosted contracts.

Only after the evidence was green did the planning files leave. Their durable facts moved into the
architecture decision, current AuraPlay reference, known limitations, QA checklist, and the shared
future-work backlog. That is the healthy lifecycle for a plan: it is scaffolding, not a second source
of truth. Once the building stands, keep the load-bearing decisions and inspection checklist; take
the scaffolding down.

## 2026-10-22 — Twelve Buildings, Not Forty-One Sheds

The package graph grew the way a useful workshop often does: every new tool got its own shed. That
made ownership easy while the runtime was being discovered, but eventually walking between forty-one
sheds became the work. The consolidation decision keeps twelve Auralis-owned buildings, plus the
vendored CodeScanner, and puts strong internal walls—Swift targets—between their rooms.

The inventory caught the most dangerous shortcut before construction started. `AuralisPrimaryModels`
looked like a convenient foundation brick, but it was actually a moving box containing principal IDs,
Ethereum chains, NFTs, playlists, search history, receipt wire formats and SwiftData models. Labeling
the whole box “Foundation” would not create architecture; it would merely hide misplaced ownership.
Those models now have recorded destination domains, and Foundation is reserved for genuinely portable
primitives, ownership vocabulary and capability vocabulary.

The strategy documents also sharpened a set of words that software loves to blur. An intent is not a
commitment. A plan is not permission. A successful HTTP request is not a fulfilled outcome. Context
is not memory, and a receipt is not proof that the human got what they wanted. Think of a restaurant:
the diner’s request, the chef’s plan, the accepted order, the ticket’s live status, the pantry’s
history, tonight’s station setup, the plated dish and the printed receipt are related, but swapping
their labels would make the kitchen dangerous. Auralis now treats those distinctions as architectural
invariants rather than prose aspirations.

One more useful surprise: much of the “missing” agent OS was already present under practical names.
Model routing, reliable event replay, actor attribution, outcome specifications, capability leases,
trusted-UI schemas, receipts and artifacts all exist. Memory and durable commitments really are new
domains; the rest should be moved and adapted, not cloned to satisfy a diagram. Good architecture is
often less about inventing abstractions than recognizing the ones the running system has already paid
to learn.

## 2026-10-22 — The Test Helper That Owned a Database

The first consolidation cut was deliberately small: remove one reverse dependency before moving any
production package. `AuralisTestSupport` was supposed to be the clean toolbox every package could
borrow, but one receipt fixture made that toolbox depend on `ReceiptStorage`. It was like requiring a
warehouse lease before borrowing a screwdriver. Any future package that used the generic fixtures
also inherited receipt persistence at the manifest level.

The source search made the right ownership pleasantly concrete. `StoredReceiptFixture` had only two
consumers, both app integration suites that already import ReceiptStorage. Moving the fixture beside
those consumers removed the shared edge without inventing a public test-support product or widening
production APIs. An architecture test now reads the manifest and source imports, so the warehouse
cannot sneak back into the toolbox.

The baseline also kept us honest: build-for-testing passed, while the full plan reported 955 passes,
four skips and two Dynamic Type audit failures in Music and Receipts. After the move, the shared
package built independently, the app built for testing, and all 22 directly affected tests passed.
The final full run was cleaner still: 962 tests, 958 passes, four skips, and zero failures. The extra
test is the new architectural tripwire, and the two baseline accessibility failures did not
reproduce. A refactor is much easier to trust when “before” and “after” are measurements rather than
vibes.

## 2026-10-23 — The Foundation Suitcase Gets Its First Two Passengers

The first real model-ownership move started with the two types that could prove their passport at
the border: `PrincipalID` and `OwnershipDescriptor`. They import only Foundation, carry no app or
blockchain behavior, and already had tests dedicated to the things they intentionally refuse to do.
That made them ideal first residents of `AuralisFoundation`.

The important part was what did *not* move. The old primary-model package also contains chains,
accounts, NFTs, playlists, music-library rows, search history, receipt payloads, and a connected
SwiftData schema. Calling that entire moving van “Foundation” would be like putting every department
in the building's lobby because everyone uses the front door. The inventory instead assigned each
family a future domain owner and left the cross-linked persistence cluster alone until its
relationships can be separated deliberately.

There are no forwarding aliases in the old module. Receipt contracts and receipt storage now import
and declare `AuralisFoundation` directly, so the compiler enforces one owner rather than letting two
names drift. The architecture test was moved with the source paths and still proves that the package
has no local or remote dependencies. A single internal target is enough for these two tightly coupled
values; more targets would currently add import ceremony without isolating a real consumer boundary.

Validation followed the dependency chain outward: 20 Foundation ownership tests, 10 remaining
primary-model tests, 68 receipt-core tests, and 207 receipt-storage tests all passed. The complete
Xcode graph also built for testing, and the relocated ownership boundary test passed in the app test
plan. The temporary package-root count rose from 42 to 43 because the destination must exist before
the mixed source package can disappear; the finish line remains 12 Auralis-owned roots plus
CodeScanner.

The full app plan ran 962 tests: 956 passed, four skipped, and the Music and Receipts Dynamic Type
audits produced the same two intermittent failures seen in the earlier baseline (they had passed on
the immediately preceding run). The package move introduced no compiler, ownership, receipt, or
persistence failures; the accessibility audits remain a separate existing issue rather than a reason
to blur the new dependency boundary.

## 2026-10-23 — The Receipt Envelope Leaves the Junk Drawer

The next three models had an equally clear address: `ReceiptJSONValue`, `ReceiptPayload`, and
`ReceiptMode` describe the receipt wire format, so they moved from the shared primary-model drawer
into `ReceiptsCore`. Callers now import the domain they actually speak. New compatibility tests pin
every JSON value shape, the payload's keyed wrapper, and the exact `Observe`/`Assist`/`Operate` raw
values—the serialized envelope did not change just because its filing cabinet did.

The source review also stopped this slice from becoming overconfident. `ReceiptActorDetail` and
`ReceiptAuthorityDetail` look like obvious neighbors, but Runtime currently owns conversions to and
from them, and Autopilot passes a receipt-shaped actor into Policy. Moving those types mechanically
would make Runtime depend on Receipts, pointing the final package graph backwards. That is the
architectural equivalent of moving the mailbox indoors and then routing the street through the
living room. Those types stay temporarily shared until Policy accepts policy/runtime attribution and
the receipt mapping can live on the outer receipt/host boundary.

The moved vocabulary is guarded twice: `ReceiptsCore` owns the only public definitions, and an app
architecture test rejects copies returning to PrimaryModels. Validation stayed pleasantly boring:
the remaining PrimaryModels tests passed, ReceiptsCore grew from 68 to 71 passing tests, PolicyCore
passed all 10 tests, ReceiptStorage passed all 207 tests, and Xcode built the complete test graph.
The full app plan then ran 963 tests: 958 passed, four skipped, and the existing intermittent Music
Dynamic Type audit was the sole failure. The new 963rd app-plan test is the receipt-ownership
tripwire, and it passed.

## 2026-10-23 — Policy Stops Asking for a Receipt Before the Decision

The next dependency knot was subtle: Policy's public action gate asked callers for a
`ReceiptActorDetail`. That is like asking someone to fill out the audit log before the guard has even
decided whether the door may open. It made Autopilot translate Runtime's canonical `ActorRef` into a
receipt wire value merely to request authorization, and it prevented the receipt actor models from
moving to their rightful package without pulling Receipts backward into Runtime.

`PolicyActionGating` now accepts `RuntimeCore.ActorRef` directly. Autopilot and RuntimeKit preserve
the same attribution value through the decision path; only `ActionPolicyGate`, where the decision is
actually recorded, converts it into receipt form. An architecture test rejects receipt actor models
from returning to the public policy interface.

This is intentionally half of a bridge move, not a claim that the whole knot is untied. RuntimeCore
still owns bidirectional receipt conversion extensions used by receipt-producing outer layers. The
next slice moves those conversions outward and then moves `ReceiptActor`, `ReceiptActorDetail`, and
`ReceiptAuthorityDetail` into ReceiptsCore. The dependency compass remains simple: Receipts may know
Runtime; Runtime must not know Receipts.

## 2026-10-23 — The Mailbox Moves Back Outside

The second half of the attribution move put the receipt-shaped models and their translation code in
ReceiptsCore. Runtime now describes actors and authority in its own language; Receipts knows how to
file those facts into durable columns. The street no longer runs through Runtime merely because the
mail carrier needs to translate an address.

One useful protocol-boundary lesson surfaced in the move. The old bridge called Runtime's internal
reconstruction helper because it lived inside the same module. Moving the adapter outward revealed
the real contract Runtime needed to publish: a tolerant initializer for raw actor kinds read from
durable storage. That initializer does not mention receipts. Any future persistence adapter can use
it while Runtime remains ignorant of the adapter and its wire schema.

The bridge-heavy tests moved with ReceiptsCore; purely runtime serialization and identity behavior
remains tested in RuntimeCore. An architecture guard now checks both halves of ownership: the three
receipt attribution declarations exist only in ReceiptsCore, and RuntimeCore cannot quietly reclaim
the conversion file.

The independent package lanes are green—240 RuntimeCore tests and 115 ReceiptsCore tests. The app
sources also compile. Xcode then exposed an honest project-configuration dependency: six app tests
now import and call RuntimeCore directly, but the `AuralisTests` target links ReceiptsCore and not the
RuntimeCore package product. Depending on a transitive static product happened to work before this
graph move, but it was accidental. The durable fix is to add RuntimeCore explicitly to the test
target in Xcode; editing the live project file behind Xcode's back is intentionally off limits.

After RuntimeCore was added through Xcode, build-for-testing and all four focused app integration
tests passed. The complete app plan did not return a result after an extended run and was cancelled;
that is recorded as an incomplete runner result rather than being rounded up into a green claim.

## 2026-10-23 — Three Engines, One Garage

The first reduction in physical package count combines the media contracts, audio engine, and video
engine under `AuraPlayEngines`. Nothing was melted into one module: the same three library products,
two demos, and three test targets remain, and Audio/Video still point inward to MediaCore. We removed
driveways, not walls.

That distinction matters. Swift targets preserve compile-time boundaries and test ownership, while
one package root removes three manifests, two inter-package path edges, and repeated package
resolution work. The unified package passed all of its existing lanes: 77 video tests, 37 media-core
tests, and 72 audio tests. The Xcode side then exposed an easy-to-miss detail: adding a local package
offers every product, including demo executables, but the app only wants the three library products.
After the three retired references and accidental demo links were removed, build-for-testing passed
with no errors. The dependency guards and complete app-hosted AuraPlay orchestration suite followed
at 24/24. The garage now has one address, three correctly labelled work bays, and no demo cars welded
to the shipping app.

## 2026-10-23 — Capabilities Moved Into The Foundation, Not Into Policy

`CapabilitiesCore` was already the architectural equivalent of a pocket dictionary: stable IDs,
categories, descriptors, use context, and a conservative registry, with no dependency on the people
using those words. Giving that dictionary its own building added routing work without buying another
wall. It now lives as an independent target and product inside `AuralisFoundation`; Runtime, Policy,
Music, and the app still say `import CapabilitiesCore`, so this move changes package ownership rather
than meaning.

The distinction from policy remains important. A capability says what may be requested; policy says
whether a particular request may proceed. Combining those modules would let vocabulary depend on
enforcement and point the dependency graph outward. Instead, the dependency-free target retained its
four wire-format and registry tests, and an architecture guard now prevents the retired root from
quietly returning. Foundation passed 24 tests, Runtime 240, Policy 10, MusicFeature 133, the Xcode
build-for-testing passed, and both package/import guards stayed green.

## 2026-10-23 — The Generic Tool Drawer Joined Foundation

The SwiftData and UserDefaults helpers were small package roots with good internal boundaries but no
domain of their own. One wraps rollback-safe and undoable `ModelContext` mutations; the other is
already generic over `Record: Codable & Sendable`. They belong in Foundation's tool drawer, not in
separate buildings and definitely not inside account, receipt, token, or artifact storage.

Their module names, products, and independent test targets survived the move. The interesting snag
was test architecture: the UserDefaults suite imported `AuralisTestSupport` for one temporary-suite
helper, which would eventually point Foundation outward toward its own consumer. A tiny local fixture
removed that reverse edge. Another useful tripwire appeared when ReceiptStorage declared the same
Foundation package twice for two products; the dependent-package run caught the duplicate identity
before Xcode did. Foundation finished at 34 green tests, its four SwiftData consumers at 248/248,
and build-for-testing plus both architecture guards passed after the Xcode references were cleaned.

## 2026-10-23 — Freshness Followed The Tokens

The mixed primary-model package still had one clock on its wall: the twelve-hour ERC-20 metadata
freshness policy. The source inventory showed that only TokenStorage production behavior and two
token presentation suites used it. That made ownership pleasantly unambiguous—the clock belongs
beside the records whose freshness it measures.

The policy moved without changing its API, and TokenStorage gained direct tests for the second before
the boundary, the boundary itself, and a future timestamp. An architecture guard prevents the type
from drifting back into PrimaryModels. PrimaryModels remained 10/10, TokenStorage moved to 10/10,
build-for-testing passed, and both presentation suites plus the guard passed at 22/22.

The same inventory found something even less model-like: `PrimaryStoreCopy` was two strings shown
when app-launch persistence fails, and only `AuralisApp` used it. It moved beside that composition
root instead of being promoted into another shared module. The rule is useful beyond this one file:
not every reusable-looking struct is a domain model, and a type with one presentation owner should
not make the entire package graph carry its vocabulary. Build-for-testing and the ownership guard
both stayed green after the move.

## 2026-10-23 — One JSON Vocabulary, Two Different Ledgers

The generic `JSONValue` had outgrown its accidental home in PrimaryModels. Provider responses, NFT
metadata, music discovery, app helpers, and test fixtures all used it without caring about any
primary persisted model. The inventory also found a second private JSON enum inside MusicFeature,
doing the same recursive coding job with a slightly different number case. That was a warning flare:
the shared primitive was real, but its owner was wrong.

The canonical enum now lives in dependency-free Foundation, conforms to `Equatable`, and keeps
integer and fractional numbers distinct under tests. MusicFeature uses it instead of maintaining a
look-alike. Receipt JSON deliberately remains separate because it is persisted receipt wire
vocabulary, not a general provider payload. The affected package suites passed—23 Foundation, 10
PrimaryModels, 52 NFTKit, 22 ProviderKit, and 133 MusicFeature tests—followed by build-for-testing and
both dependency guards after the app linked Foundation explicitly.

## 2026-10-23 — Empty Suitcases Do Not Need A New Address

The PrimaryModels inventory found five polished-looking portable values for NFTs, token holdings,
playlists, and search history. They had initializers, Codable conformance, and absolutely no callers.
They were architectural luggage packed for a trip nobody had booked. Moving them into the planned
domain packages would have made the diagram tidier while preserving speculative APIs as if they were
requirements.

Those unused values were deleted instead. `AccountSummary` remains because AccountsFeature and the
home surface genuinely exchange it. An architecture tripwire now prevents the five speculative
types from quietly returning without consumers. The same investigation also caught a more serious
constraint: AccountStorage currently deletes and snapshots account, token, music, search, and NFT
records inside one rollback-safe SwiftData mutation. Replacing that with ordinary cleanup callbacks
would create prettier imports at the cost of partial deletion and broken undo. The future seam must
move the transaction boundary with the orchestration—or provide transaction-aware adapters—not just
paint a protocol over the existing coupling.

## 2026-10-23 — The Undo Button Had Two Missing Boxes

Before turning account cleanup into a protocol, we checked what its transaction actually promised.
The answer was slightly alarming: removing an account deleted its indexed music rows, but the manual
undo snapshot did not pack them for the return trip. NFT attributes were packed, then left sitting in
the snapshot while the restored NFT was built without them. Undo brought the house back but forgot
the record collection and some labels on the art.

`MusicLibraryItemSnapshot` now preserves every stored music-index field, and NFT restoration rebuilds
the captured attributes. The focused integration test inserts both, removes the account, verifies the
rows disappear, invokes undo, and verifies their meaningful values return. This is also the shape of
the future package boundary: domain adapters should own complete snapshot/delete/restore behavior,
while one coordinator owns the shared SwiftData transaction. Independent cleanup callbacks would be
easier to draw and much harder to trust.

The invariant now also lives beside its implementation in `AccountStorageTests`, so the package will
carry the contract when it leaves the app graph. Xcode's generated AccountStorage scheme compiled
successfully but advertised zero tests in its test plan—a useful reminder that a green package build
is not a package test run. The executable app-hosted undo and architecture checks both passed after
the scheme was restored; the owner-package test remains explicitly pending the repository's package
test lane.

## 2026-10-23 — One Transaction, Four Moving Crews

AccountStorage's cleanup knot now has an actual seam. Token holdings, indexed music, search history,
and NFTs each implement the same capture/delete/restore participant protocol. Think of them as four
moving crews working inside one building: each knows how to pack its own room, but only the building
manager holds the master key and closes the transaction. Participants cannot save, commit, or open a
second context.

This keeps rollback and undo honest while making the eventual package move mechanical: each
participant can travel with its domain model once the destination target exists. Build-for-testing
passed, followed by focused overwrite, removal/fallback, undo, and architecture checks at 4/4. An
architecture tripwire now requires all four participants and their common protocol to remain present
until they are replaced by the final injected domain adapters.

Then the fire drill earned its keep. A test-only hook stopped removal immediately after the music
participant, late enough that token and music cleanup had already run. `performRollbackSafeMutation`
called rollback exactly as designed—but SwiftData's typed batch-delete API had already made those rows
disappear. The account and NFTs returned; the token and music records did not. Our “one transaction”
sign was hanging over two trapdoors.

Account-scoped participants now fetch matching records and delete the model instances through the
shared context. Those deletes participate in rollback correctly. The injected failure test now keeps
the account plus all four domain record families intact, and the existing overwrite, fallback, undo,
and architecture regressions remain green. This is why migration tests need forced failures: happy
paths can make a non-atomic system look perfectly atomic.

## 2026-10-23 — The Moving Crews Went Home To Their Domains

The transaction protocol shed its account-specific name and moved into the Foundation SwiftData
toolbox as `ScopedPersistenceParticipant`. It knows only that a caller supplies a scope, a context,
and ownership of the transaction. That is enough structure for strong generic composition without
teaching Foundation what a wallet, token, song, or NFT is.

The token crew moved first: TokenStorage now owns the full value snapshot and the code that captures,
deletes, and restores `TokenHolding`. NFT persistence followed, taking its snapshot and cleanup rules
with it. That move also retired a duplicate cleanup implementation in AccountStorage; orphan
contracts, collections, and tags now have one owner. AccountStorage is becoming the conductor rather
than a musician who somehow plays every instrument. Build-for-testing stayed green, and the five
focused rollback, undo, overwrite, package-graph, and NFT-layer checks passed.

The first NFT-owner test then opened boxes the old snapshot never packed: external and background
metadata, image and raw-metadata children, tags, and playlist membership. All eight checks failed on
the first run. NFTPersistence now reconstructs the child records, reuses or recreates tags by name,
and reconnects surviving playlists by stable ID. Undo fidelity and forced transaction rollback both
pass, so moving cleanup ownership did more than tidy imports—it exposed and repaired real data loss.

Three smaller pieces then followed their actual callers. `AccountSummary` moved into AccountsCore,
leaving the speculative portable-values file empty enough to delete. Native-token symbols and labels
moved beside TokenStorage, their only consumer. Finally, `NFT.musicURL` and its HTTPS/IPFS sanitation
policy moved into MusicFeature: choosing a playable audio URL is music behavior, not an obligation of
every persisted NFT. These are small moves, but they shave accidental responsibilities off the mixed
model package without inventing replacement abstractions.
