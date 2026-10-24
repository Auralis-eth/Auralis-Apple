# Ownership and Sovereignty

> **Status: Complete (2026-10-22).** The Phase 1 ownership and sovereignty restructuring is
> implemented, audited, documented, and protected by architecture tests. “Complete” covers the
> vocabulary, package boundaries, authority separation, receipt schema/integrity support, and the
> permanent-root-owner audit defined here. Production adoption of the optional provenance fields and
> any future governance or economic system are separately scoped follow-ons; they do not reopen this
> restructuring.

This document establishes how Auralis talks about ownership, and what that commits the code to. It is
an architecture document: every principle below is followed by the repository constraint it implies,
because a principle with no constraint attached is a preference rather than an architecture.

Companion documents: [`FOUNDERS_COVENANT.md`](FOUNDERS_COVENANT.md) states the philosophical position
this document encodes. [`AGENTS.md`](AGENTS.md) carries the package boundaries that implement it.

## Principles

### Formation

Auralis begins founder-owned and centrally controlled during bootstrap. Someone has to decide the
shape of a system before there is a system to decide anything about, and pretending otherwise produces
either paralysis or a governance theatre with no underlying substance.

Centralized creation does not imply permanent centralized ownership of every network Auralis creates.
Those are separate claims, and conflating them is the specific mistake this document exists to prevent.
The first is a fact about how work gets started; the second would be a standing assertion about who
may always decide, and nothing about formation establishes it.

Mature networks may eventually transition toward participant ownership or governance. Decentralization
is an outcome of maturity, not a launch feature: a network becomes capable of being owned by its
participants when it has participants, a real resource to coordinate, and enough operating history for
the transition not to be a transfer of unmeasured risk.

### Separation of entities

Auralis Inc., the protocols it publishes, the networks those protocols constitute, the resources those
networks coordinate, the artifacts produced inside them, and the participants who act in them are
conceptually separate entities. Each can be named without the others. None of them is a synonym for
any other, and none of them is the default answer to a question about the others.

Protocols must remain architecturally capable of separation from Auralis Inc. "Capable of separation"
is a structural property, not an intention: a protocol package that only compiles against this app's
composition root is not separable, whatever the roadmap says about it.

### Roles

Creator, owner, controller, custodian, and beneficiary are not synonymous. One principal may hold
several of these roles, and frequently will — but that is a fact about a particular resource at a
particular time, not an invariant the models may assume. The interesting cases are precisely the ones
where the roles come apart: a work created by one person, owned by a second, operated by a third, held
in custody by a fourth, and yielding its benefit to a fifth.

No subsystem may assume Auralis Inc. is the permanent root owner unless a named bootstrap policy
explicitly requires it. A bootstrap exception is legitimate; an unnamed one that quietly hardens into
a domain invariant is not.

### Tokens and contribution

Tokens must represent a real resource, right, productive asset, or coordination function. A token that
represents nothing is a claim on nothing, and issuing one is a way of extracting value rather than
coordinating it.

Contribution records do not automatically imply equity, tokens, compensation, or ownership. Auralis
records what happened — who acted, under what authority, affecting what, producing what — because an
accurate account of events is independently worth having. A future economic system may read that
history, but it must apply its own explicit policy and its own evidence; the history itself asserts
nothing about who is owed what.

Ownership metadata describes relationships; it does not grant authority by itself. A record saying
that a principal is the owner of a resource is a statement, not a key.

## Repository constraints

These are the constraints the principles above translate into. They are enforced by
`AuralisTests/ArchitectureBoundaryTests.swift` where they are mechanically checkable, and by review
where they are not.

### 1. Foundational packages do not depend on app composition

Foundational protocol and domain packages must not depend on app composition or an Auralis-owned
singleton. Concretely: `AuralisFoundation`, `AuralisPrimaryModels`, `CapabilitiesCore`, `RuntimeCore`, `ReceiptsCore`,
`ArtifactCore` and `PolicyCore` must not import the app target, a feature package, or a composition
root, and must not reach a service through a globally-reachable shared instance.

This is what "architecturally capable of separation" means in practice. It is already pinned by the
ADR-008 layering test and by the per-target import rules; the ownership models inherit both.

### 2. Ownership models default no role to an Auralis-controlled principal

Ownership models **must not default any role** to an Auralis-controlled principal.
`OwnershipDescriptor` makes every role independently optional and defaults every one of them to
absent. There is no `OwnershipDescriptor.auralis`, no implicit creator, and no fallback owner. An
absent role means *not stated*, which is different from *held by us*.

A descriptor also never resolves a role from another role. Nothing infers that the creator is the
owner, or that the owner is the controller, because the whole point of five separate roles is that
those inferences are not sound.

### 3. Authorization receives explicit context

Authorization APIs must receive explicit actor, capability, policy, and resource context where those
concepts apply. Authorization in Auralis is conceptually **principal + capability + policy +
resource**, and each leg arrives as an argument rather than being read from ambient state.

`PrincipalID` deliberately does not participate in this. It is an opaque label attached to ownership
*relationships*; the runtime's answer to "who acted" is `RuntimeCore.ActorRef`, which is a richer and
separately validated model. A bridge between the two must be explicit and must not invent a principal
where stable identity is unavailable.

### 4. A bootstrap exception names its policy

Where bootstrap genuinely requires centralized control, the code must name the policy that requires
it, so that the exception is searchable and removable. An exception that is not attributable to a
named policy is indistinguishable from an assumption, and assumptions do not get retired.

### 5. Ownership metadata grants no authority

No authorization decision may read an `OwnershipDescriptor`. The descriptor carries no methods that
answer a permission question, holds no capabilities, and is not consulted by `PolicyCore`,
`CapabilitiesCore` or the governed tool pipeline. If a future feature needs "the owner may do X", that
rule belongs in policy, with ownership as one input among several and the decision recorded on a
receipt.

### 6. Identity stays opaque

`PrincipalID.rawValue` carries no semantics. Consumers may compare, store, serialize, and pass it;
they must not parse it to infer whether the principal is a person, agent, organization, wallet,
blockchain address, DID, protocol, network, or anything else. Branching authorization, presentation,
routing, or persistence behaviour on the *contents* of a raw value is the defect this constraint
exists to prevent — it turns a label into an unversioned, unvalidated type system that every consumer
reimplements slightly differently.

### 7. Contribution provenance stays separate from economics

Receipt models contain no token, equity, ownership-percentage, governance-weight, or financial-reward
semantics, and must not acquire any. The boundary is checked structurally: see the economic-boundary
test in `ReceiptStorage`, which fails if a prohibited field name appears on the receipt contracts.

## What this document does not do

It does not create an ownership registry, a transfer mechanism, a governance process, or an economic
system. There is no Auralis or AURA token, no treasury, no staking, no voting, and no on-chain
identity. Those are deliberate absences rather than unfinished work: the vocabulary has to be able to
*describe* separable ownership before it is safe to build anything that acts on it.
