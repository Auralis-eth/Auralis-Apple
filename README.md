# Auralis

**An Apple-native operator shell for people who want wallet-scoped identity, asset visibility, and AI-assisted onchain workflows without giving up control.**

Auralis solves the mess of fragmented wallets, scattered asset context, thin trust signals, and unsafe agent hype by giving users a governed, read-only shell first — with receipts, scoped context, and clear authority boundaries built in.

## What you can do today

Today, Auralis is a working **read-only governed shell** on iOS.

You can:
- restore a wallet address or guest-pass account
- scope the app to an account + chain context
- fetch NFTs and token holdings through provider-backed read-only services
- browse shared product surfaces like Home, Search, Tokens, Receipts, News, and Music
- inspect context and freshness state
- view append-only receipts for operational history

Auralis is **not** a signing wallet today.  
It is the trust-first shell that comes before deeper operator flows.

## Why this exists

Most crypto apps make you choose between:
- fragmented wallet UX
- poor visibility across assets and context
- AI systems with unclear authority
- automation without legibility or receipts

Auralis takes a different path:

- **read-only first**
- **policy-aware by design**
- **receipt-backed**
- **wallet-scoped**
- **built for bounded operators later**

The goal is not “agent chaos.”
The goal is a product people can actually trust with real authority over time.

## Product direction

Auralis is becoming a **control plane for trusted autonomy**:

- Mission Control for ongoing work
- bounded operators
- confirm-first Web3 actions
- durable artifacts
- scheduling and routines
- plugin-safe expansion
- user-owned model choice over time

The MVP starts Apple-native, then expands toward more user-sovereign model support later. :contentReference[oaicite:3]{index=3} :contentReference[oaicite:4]{index=4}

## Architecture at a glance

Auralis is organized around five layers:

1. **Shell** — active account, chain scope, routing, and root surfaces
2. **Services** — providers, context building, receipts, balances, holdings, NFT refresh
3. **Persistence** — SwiftData models for accounts, NFTs, holdings, receipts, playlists, and related state
4. **Feature surfaces** — Home, Search, News, Tokens, Receipts, Music
5. **Chrome and policy** — global chrome, trust labels, mode state, safe action wrappers

If a bug feels global, it is usually in shell state, scoped persistence, routing, or shared services rather than a single leaf view. :contentReference[oaicite:5]{index=5}

## Current status

**Phase 0 is effectively complete for the current slice.**

That means the repo already has:
- app shell and global chrome
- Home, Search, Music, and token surfaces
- provider-backed holdings
- context builder + context inspector
- append-only receipts
- Observe-mode posture and policy boundaries
- degraded/cached behavior as part of the intended product path

The next major phase is turning this trusted shell into a real operator console. :contentReference[oaicite:6]{index=6} :contentReference[oaicite:7]{index=7}

## Try it

### Requirements
- Xcode
- Apple platform simulator or device
- Access to the `SEED` branch

### Run locally
```bash
git clone https://github.com/Auralis-eth/Auralis-Apple.git
cd Auralis-Apple
git checkout SEED
open Auralis/Auralis.xcodeproj
```

## Docs worth reading

- `AGENTS.md`
- `Journal.md`
- `Auralis/P0-Implementation-Order-Plan.md`
- `Auralis/P0-Hard-Closeout-Report.md`
- `P0-Future-Work.md`

## Roadmap

### Completed

Operator Foundations / trusted read-only shell

### Next

- Mission Control
- Approval Inbox
- Capability Inspector
- artifact-producing operators
- scheduling/routines
- confirm-first Web3 operator flows

### Longer term

- bounded autopilot
- plugin ecosystem
- user-sovereign model expansion

## Philosophy

Auralis is being built around one belief:

Powerful software should act under human-readable, user-owned control.

---

## What to change at the very top

Your top section needs to hit the four questions fast.

I’d use this exact structure:

1. **Who is this for?**  
   “People living onchain who want wallet-scoped identity, asset visibility, and AI-assisted workflows without surrendering control.”

2. **What painful problem does it solve?**  
   “Crypto users juggle fragmented wallets, thin trust signals, scattered context, and unsafe automation.”

3. **What can someone do today?**  
   “Run a local read-only governed shell that restores account scope, fetches NFTs/tokens, and shows receipts, context, and shared surfaces.”

4. **What is the next step?**  
   “Clone the repo, run the SEED branch, and explore the shell.”

---
